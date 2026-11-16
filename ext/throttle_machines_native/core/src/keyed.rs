//! Keyed GCRA: one TAT per key in a sharded, mutex-guarded map.
//!
//! A TAT at or before `now` is equivalent to no entry (the key has fully
//! recovered), which is what eviction relies on. The caller supplies `now`,
//! the same epoch for every call on one limiter; threads racing on one shard
//! may present slightly out-of-order instants, which GCRA answers no more
//! generously than in order.

use std::borrow::{Borrow, ToOwned};
use std::boxed::Box;
use std::collections::HashMap;
use std::hash::{BuildHasher, Hash, RandomState};
use std::num::NonZeroUsize;
use std::sync::{Mutex, MutexGuard, PoisonError};
use std::time::Duration;
use std::vec::Vec;

use crate::{Gate, Gcra, GcraPolicy, Refusal};

const DEFAULT_SHARDS: NonZeroUsize = NonZeroUsize::MIN.saturating_add(15);
const DEFAULT_MAX_KEYS_PER_SHARD: NonZeroUsize = NonZeroUsize::MIN.saturating_add(4095);
/// Start sweeping a shard of recovered keys at this many entries.
const DEFAULT_EVICT_AT: usize = 4096;
/// An automatic sweep waits until this fraction of the shard could have
/// recovered, so each one reclaims a batch instead of rescanning for one key.
const SWEEP_BATCH: usize = 8;

#[derive(Debug)]
struct Shard<K> {
    tats: HashMap<K, Duration>,
    // When the next automatic sweep may run; `None` runs it at once.
    next_sweep: Option<Duration>,
}

impl<K> Shard<K> {
    fn sweep_open(&self, now: Duration) -> bool {
        self.next_sweep.is_none_or(|deadline| deadline <= now)
    }

    /// Reclaim recovered keys, unless too few could have recovered yet.
    fn sweep_due(&mut self, now: Duration) {
        if self.sweep_open(now) {
            self.sweep(now);
        }
    }

    /// Whether [`sweep_due`](Self::sweep_due) at `now` would free a slot.
    fn reclaimable(&self, now: Duration) -> bool {
        self.sweep_open(now) && self.tats.values().any(|tat| *tat <= now)
    }

    /// Reclaim every recovered key and schedule the next automatic sweep
    /// for when an eighth of those left could have recovered.
    fn sweep(&mut self, now: Duration) {
        self.tats.retain(|_, tat| *tat > now);
        let mut tats: Vec<Duration> = self.tats.values().copied().collect();
        self.next_sweep = (!tats.is_empty()).then(|| {
            // 1 <= batch <= len for a non-empty set, so `batch - 1` is in bounds.
            let batch = (tats.len() / SWEEP_BATCH).max(1);
            *tats.select_nth_unstable(batch - 1).1
        });
    }
}

/// What a key finds in its shard, for the queries.
enum Seen {
    /// The key is tracked at this TAT.
    Tracked(Duration),
    /// The key is untracked and `check` would refuse it as full; the shard's
    /// next sweep, if one is scheduled.
    Full(Option<Duration>),
    /// The key is untracked and would be admitted from a fresh TAT.
    Room,
}

/// A GCRA limiter that keeps per-key state itself.
///
/// Every key is limited by one [`GcraPolicy`]. A refused call leaves every
/// key's TAT as it was; a [`Refusal::Full`] may still reschedule the shard's
/// next sweep, which is bookkeeping, not limiter state.
///
/// ```
/// use core::num::NonZeroU64;
/// use std::time::Duration;
/// use throttle_machines::{GcraPolicy, KeyedGcra, Refusal};
///
/// let one = NonZeroU64::MIN;
/// let policy = GcraPolicy::per(Duration::from_secs(1), one, one).unwrap();
/// let limiter = KeyedGcra::<String>::new(policy);
/// let now = Duration::from_secs(3);
/// assert_eq!(limiter.check("alice", now), Ok(0));
/// assert_eq!(limiter.check("alice", now), Err(Refusal::Throttled));
/// assert_eq!(limiter.check("bob", now), Ok(0));
/// ```
#[derive(Debug)]
pub struct KeyedGcra<K, S = RandomState> {
    policy: GcraPolicy,
    shards: Box<[Mutex<Shard<K>>]>,
    hasher: S,
    evict_at: usize,
    max_keys_per_shard: NonZeroUsize,
}

impl<K: Hash + Eq> KeyedGcra<K> {
    /// A limiter with 16 shards of up to 4096 keys and a randomly seeded
    /// hasher.
    #[must_use]
    pub fn new(policy: GcraPolicy) -> Self {
        Self::with_hasher(
            policy,
            DEFAULT_SHARDS,
            DEFAULT_MAX_KEYS_PER_SHARD,
            RandomState::new(),
        )
    }
}

impl<K: Hash + Eq, S: BuildHasher> KeyedGcra<K, S> {
    /// A limiter with `shards` independently locked maps of up to
    /// `max_keys_per_shard` keys each, hashed by `hasher`.
    ///
    /// Recovered keys are reclaimed first, in batches: a full shard sweeps
    /// once an eighth of it could have recovered, and refuses unknown keys
    /// with [`Refusal::Full`] until then without allocating; tracked keys
    /// keep their limits. Unused capacity in another shard is not borrowed.
    #[must_use]
    pub fn with_hasher(
        policy: GcraPolicy,
        shards: NonZeroUsize,
        max_keys_per_shard: NonZeroUsize,
        hasher: S,
    ) -> Self {
        Self {
            policy,
            shards: (0..shards.get())
                .map(|_| {
                    Mutex::new(Shard {
                        tats: HashMap::new(),
                        next_sweep: None,
                    })
                })
                .collect(),
            hasher,
            evict_at: DEFAULT_EVICT_AT,
            max_keys_per_shard,
        }
    }

    /// Sweep recovered keys after an admission leaves a shard with at least
    /// `evict_at` entries (default 4096). A cleanup trigger, not a cap.
    /// Sweeps are skipped until an eighth of the shard could have recovered.
    #[must_use]
    pub const fn evict_at(mut self, evict_at: usize) -> Self {
        self.evict_at = evict_at;
        self
    }

    /// The policy every key is limited by.
    #[must_use]
    pub const fn policy(&self) -> GcraPolicy {
        self.policy
    }

    /// Admit one call for `key` at `now`. Honoured: how many more calls the
    /// key would be admitted at the same instant.
    ///
    /// # Errors
    ///
    /// [`Refusal::Throttled`] when the key's limit is spent at `now`;
    /// [`Refusal::Overflow`] when admitting would push its TAT past
    /// `Duration::MAX`; [`Refusal::Full`] when the key is untracked and its
    /// shard is full of keys that have not recovered.
    pub fn check<Q>(&self, key: &Q, now: Duration) -> Result<u64, Refusal>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ToOwned<Owned = K> + ?Sized,
    {
        let mut shard = self.shard(key);
        let left = if let Some(tat) = shard.tats.get_mut(key) {
            let mut gcra = Gcra::restored(self.policy, *tat);
            let left = gcra.check(now)?;
            *tat = gcra.tat();
            left
        } else {
            if shard.tats.len() >= self.max_keys_per_shard.get() {
                // Frees a slot exactly when a key has recovered; otherwise
                // it only reschedules the next sweep.
                shard.sweep_due(now);
                if shard.tats.len() >= self.max_keys_per_shard.get() {
                    return Err(Refusal::Full);
                }
            }
            let mut gcra = Gcra::new(self.policy);
            let left = gcra.check(now)?;
            shard.tats.insert(key.to_owned(), gcra.tat());
            left
        };
        if shard.tats.len() >= self.evict_at {
            shard.sweep_due(now);
        }
        drop(shard);
        Ok(left)
    }

    /// How many calls [`check`](Self::check) would admit `key` at `now`, at
    /// least one, without consuming or reclaiming anything.
    ///
    /// # Errors
    ///
    /// The refusal `check` would answer at `now`.
    pub fn peek<Q>(&self, key: &Q, now: Duration) -> Result<u64, Refusal>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        match self.seen(key, now) {
            Seen::Tracked(tat) => Gcra::restored(self.policy, tat).peek(now),
            Seen::Full(_) => Err(Refusal::Full),
            Seen::Room => Gcra::new(self.policy).peek(now),
        }
    }

    /// How long after `now` `key` is admitted: zero when it is admitted at
    /// `now`. For an untracked key refused as full, the wait until its shard
    /// next sweeps, a hint rather than a promise of a free slot.
    pub fn retry_after<Q>(&self, key: &Q, now: Duration) -> Duration
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        match self.seen(key, now) {
            Seen::Tracked(tat) => Gcra::restored(self.policy, tat).retry_after(now),
            Seen::Full(next_sweep) => {
                next_sweep.map_or(Duration::ZERO, |deadline| deadline.saturating_sub(now))
            }
            Seen::Room => Gcra::new(self.policy).retry_after(now),
        }
    }

    /// Give back one admission [`check`](Self::check) granted `key`, as if
    /// it had been refused: for admitting a call only when every limiter it
    /// spends admits it. A key left fully recovered at `now` is dropped,
    /// freeing its slot; an untracked key has nothing to give back.
    pub fn refund<Q>(&self, key: &Q, now: Duration)
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let mut shard = self.shard(key);
        let Some(tat) = shard.tats.get_mut(key) else {
            return;
        };
        let mut gcra = Gcra::restored(self.policy, *tat);
        gcra.refund();
        *tat = gcra.tat();
        if *tat <= now {
            shard.tats.remove(key);
        }
    }

    /// Drop every key that has fully recovered at `now`; answers how many.
    pub fn evict(&self, now: Duration) -> usize {
        self.shards
            .iter()
            .map(|shard| {
                let mut shard = lock(shard);
                let before = shard.tats.len();
                shard.sweep(now);
                // A sweep only removes keys.
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

    /// What `key` finds in its shard at `now`, read under one short lock.
    fn seen<Q>(&self, key: &Q, now: Duration) -> Seen
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let shard = self.shard(key);
        let seen = match shard.tats.get(key) {
            Some(tat) => Seen::Tracked(*tat),
            None if shard.tats.len() >= self.max_keys_per_shard.get()
                && !shard.reclaimable(now) =>
            {
                Seen::Full(shard.next_sweep)
            }
            None => Seen::Room,
        };
        drop(shard);
        seen
    }

    fn shard<Q: Hash + ?Sized>(&self, key: &Q) -> MutexGuard<'_, Shard<K>> {
        // Built from a `NonZeroUsize`, so `count` is never zero.
        let count = self.shards.len() as u64;
        // Reduced modulo the shard count, so the index fits a usize.
        let index = usize::try_from(self.hasher.hash_one(key) % count).unwrap_or(0);
        #[allow(
            clippy::indexing_slicing,
            reason = "index < count = shards.len(): reduced modulo the length just above"
        )]
        let shard = &self.shards[index];
        lock(shard)
    }
}

/// TATs are plain durations, so a poisoned shard is still consistent.
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

#[cfg(test)]
mod tests;
