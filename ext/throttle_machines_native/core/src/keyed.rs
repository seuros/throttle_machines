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
/// Sweep a shard of recovered keys once it grows past this many entries.
const DEFAULT_EVICT_AT: usize = 4096;

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
    shards: Box<[Mutex<HashMap<K, f64>>]>,
    hasher: S,
    epoch: Instant,
    evict_at: usize,
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
                .map(|_| Mutex::new(HashMap::new()))
                .collect(),
            hasher,
            epoch: Instant::now(),
            evict_at: DEFAULT_EVICT_AT,
        }
    }

    /// Sweep a shard of recovered keys whenever an admission grows it past
    /// `evict_at` entries (default 4096).
    #[must_use]
    pub const fn evict_at(mut self, evict_at: usize) -> Self {
        self.evict_at = evict_at;
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
    pub fn check_at<Q>(&self, key: &Q, now: f64) -> Decision<f64>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ToOwned<Owned = K> + ?Sized,
    {
        let mut tats = self.shard(key);
        let tat = tats.get(key).copied().unwrap_or(0.0);
        let decision = Gcra::check(tat, now, self.params);
        if decision.allowed {
            match tats.get_mut(key) {
                Some(tat) => *tat = decision.state,
                None => {
                    tats.insert(key.to_owned(), decision.state);
                }
            }
            if tats.len() > self.evict_at {
                tats.retain(|_, tat| *tat > now);
            }
        }
        decision
    }

    /// Whether `key` would be admitted now, without consuming.
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
        let tat = self.shard(key).get(key).copied().unwrap_or(0.0);
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
                let mut tats = lock(shard);
                let before = tats.len();
                tats.retain(|_, tat| *tat > now);
                before - tats.len()
            })
            .sum()
    }

    /// Keys currently tracked, including recovered ones not yet evicted.
    pub fn len(&self) -> usize {
        self.shards.iter().map(|shard| lock(shard).len()).sum()
    }

    /// Whether no key is tracked.
    pub fn is_empty(&self) -> bool {
        self.shards.iter().all(|shard| lock(shard).is_empty())
    }

    fn shard<Q: Hash + ?Sized>(&self, key: &Q) -> MutexGuard<'_, HashMap<K, f64>> {
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
