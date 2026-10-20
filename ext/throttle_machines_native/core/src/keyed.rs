//! Keyed GCRA: one TAT per key in a sharded map, on a monotonic clock.
//!
//! A TAT at or before `now` is equivalent to no entry (the client has fully
//! recovered), which is what eviction relies on.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::{BuildHasher, Hash, RandomState};
use std::num::NonZeroUsize;
use std::sync::{Mutex, MutexGuard, PoisonError};
use std::time::Instant;

use crate::gate::{Decision, Gate};
use crate::gcra::{Gcra, GcraParams};

const DEFAULT_SHARDS: NonZeroUsize = NonZeroUsize::new(16).expect("16 is non-zero");
/// Start sweeping a shard of recovered keys at this many entries.
const DEFAULT_EVICT_AT: usize = 4096;
const DEFAULT_MAX_KEYS_PER_SHARD: usize = 4096;

#[derive(Debug)]
struct Shard<K> {
    tats: HashMap<K, f64>,
    // Lower bound on the next recovery. Stale early deadlines are safe.
    next_sweep: Option<f64>,
}

impl<K> Shard<K> {
    fn sweep(&mut self, now: f64) {
        if self.next_sweep.is_some_and(|deadline| deadline > now) {
            return;
        }
        let mut next: Option<f64> = None;
        self.tats.retain(|_, tat| {
            if *tat <= now {
                return false;
            }
            next = Some(next.map_or(*tat, |deadline| deadline.min(*tat)));
            true
        });
        self.next_sweep = next;
    }
}

/// A GCRA limiter that keeps per-key state itself.
///
/// ```
/// use throttle_machines::{GcraParams, KeyedGcra};
///
/// let limiter = KeyedGcra::<String>::new(GcraParams::from_rate(10.0, 3));
/// assert!(limiter.check("alice").allowed);
/// ```
#[derive(Debug)]
pub struct KeyedGcra<K, S = RandomState> {
    params: GcraParams,
    shards: Box<[Mutex<Shard<K>>]>,
    hasher: S,
    epoch: Instant,
    evict_at: usize,
    max_keys_per_shard: usize,
}

impl<K: Hash + Eq> KeyedGcra<K> {
    /// A limiter with 16 shards and a randomly seeded hasher.
    #[must_use]
    pub fn new(params: GcraParams) -> Self {
        Self::with_hasher(params, DEFAULT_SHARDS, RandomState::new())
    }
}

impl<K: Hash + Eq, S: BuildHasher> KeyedGcra<K, S> {
    /// A limiter with `shards` independently locked maps, hashed by `hasher`.
    #[must_use]
    pub fn with_hasher(params: GcraParams, shards: NonZeroUsize, hasher: S) -> Self {
        Self {
            params,
            shards: (0..shards.get())
                .map(|_| {
                    Mutex::new(Shard {
                        tats: HashMap::new(),
                        next_sweep: None,
                    })
                })
                .collect(),
            hasher,
            epoch: Instant::now(),
            evict_at: DEFAULT_EVICT_AT,
            max_keys_per_shard: DEFAULT_MAX_KEYS_PER_SHARD,
        }
    }

    /// Sweep recovered keys before checking a shard with at least `evict_at`
    /// entries (default 4096). This is a cleanup trigger, not a storage cap.
    /// Sweeps are skipped until a tracked key could have recovered.
    #[must_use]
    pub const fn evict_at(mut self, evict_at: usize) -> Self {
        self.evict_at = evict_at;
        self
    }

    /// Cap each shard at `max_keys` entries (default 4096, 65536 total with
    /// the default 16 shards). Zero rejects all new identities.
    ///
    /// Recovered keys are reclaimed first. When a shard is full, unknown keys
    /// are refused without allocating; existing keys keep their rate limits.
    /// Unused capacity in another shard is not borrowed.
    ///
    /// # Panics
    ///
    /// Panics if a shard already contains more than `max_keys` entries.
    #[must_use]
    pub fn max_keys_per_shard(mut self, max_keys: usize) -> Self {
        assert!(
            self.shards
                .iter()
                .all(|shard| lock(shard).tats.len() <= max_keys),
            "max_keys cannot be smaller than an existing shard"
        );
        self.max_keys_per_shard = max_keys;
        self
    }

    /// The parameters every key is limited by.
    pub const fn params(&self) -> GcraParams {
        self.params
    }

    /// Seconds since this limiter was created: the clock `check` and `peek` use.
    pub fn now(&self) -> f64 {
        self.epoch.elapsed().as_secs_f64()
    }

    /// Admit one request for `key` now. Refusals leave the key's state untouched.
    pub fn check<Q>(&self, key: &Q) -> Decision<f64>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ToOwned<Owned = K> + ?Sized,
    {
        self.check_at(key, self.now())
    }

    /// [`check`](Self::check) at an explicit time on this limiter's clock.
    /// A full shard refuses unknown identities with state `0.0` and a retry
    /// hint until the next possible recovery, without reserving a slot.
    pub fn check_at<Q>(&self, key: &Q, now: f64) -> Decision<f64>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ToOwned<Owned = K> + ?Sized,
    {
        let mut shard = self.shard(key);
        if shard.tats.len() >= self.evict_at || shard.tats.len() >= self.max_keys_per_shard {
            shard.sweep(now);
        }
        let tat = shard.tats.get(key).copied().unwrap_or(0.0);
        if !shard.tats.contains_key(key) && shard.tats.len() >= self.max_keys_per_shard {
            return Self::capacity_refusal(&shard, now);
        }
        let decision = Gcra::check(tat, now, self.params);
        if decision.allowed {
            match shard.tats.get_mut(key) {
                Some(tat) => *tat = decision.state,
                None => {
                    shard.tats.insert(key.to_owned(), decision.state);
                }
            }
            shard.next_sweep = Some(
                shard
                    .next_sweep
                    .map_or(decision.state, |deadline| deadline.min(decision.state)),
            );
        }
        decision
    }

    /// Whether `key` would be admitted now, without consuming. May reclaim
    /// recovered keys when the shard is full.
    pub fn peek<Q>(&self, key: &Q) -> Decision<f64>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        self.peek_at(key, self.now())
    }

    /// [`peek`](Self::peek) at an explicit time on this limiter's clock.
    pub fn peek_at<Q>(&self, key: &Q, now: f64) -> Decision<f64>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let mut shard = self.shard(key);
        // Reclaiming recovered state does not consume rate-limit capacity.
        if shard.tats.len() >= self.max_keys_per_shard {
            shard.sweep(now);
        }
        let tat = shard.tats.get(key).copied().unwrap_or(0.0);
        if !shard.tats.contains_key(key) && shard.tats.len() >= self.max_keys_per_shard {
            return Self::capacity_refusal(&shard, now);
        }
        drop(shard);
        Gcra::peek(tat, now, self.params)
    }

    /// Drop every key that has fully recovered; returns how many were dropped.
    pub fn evict(&self) -> usize {
        self.evict_before(self.now())
    }

    /// [`evict`](Self::evict) at an explicit time on this limiter's clock.
    pub fn evict_before(&self, now: f64) -> usize {
        self.shards
            .iter()
            .map(|shard| {
                let mut shard = lock(shard);
                let before = shard.tats.len();
                shard.sweep(now);
                before - shard.tats.len()
            })
            .sum()
    }

    /// Keys currently tracked, including recovered ones not yet evicted.
    pub fn len(&self) -> usize {
        self.shards.iter().map(|shard| lock(shard).tats.len()).sum()
    }

    /// Whether no key is tracked.
    pub fn is_empty(&self) -> bool {
        self.shards.iter().all(|shard| lock(shard).tats.is_empty())
    }

    fn capacity_refusal(shard: &Shard<K>, now: f64) -> Decision<f64> {
        Decision {
            allowed: false,
            state: 0.0,
            // This is a capacity retry hint, not a guarantee of a free slot.
            retry_after: shard
                .next_sweep
                .map_or(1.0, |deadline| (deadline - now).max(0.0)),
        }
    }

    fn shard<Q: Hash + ?Sized>(&self, key: &Q) -> MutexGuard<'_, Shard<K>> {
        // Only the low bits pick a shard, so truncating the hash is fine.
        #[expect(
            clippy::cast_possible_truncation,
            reason = "reduced modulo the shard count"
        )]
        let index = (self.hasher.hash_one(key) % self.shards.len() as u64) as usize;
        lock(&self.shards[index])
    }
}

/// State is plain floats, so a poisoned shard is still consistent.
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

#[cfg(test)]
mod tests;
