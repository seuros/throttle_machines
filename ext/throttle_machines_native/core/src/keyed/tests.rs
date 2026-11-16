use std::num::NonZeroU64;
use std::string::String;
use std::thread;
use std::vec::Vec;

use super::*;

const fn ms(value: u64) -> Duration {
    Duration::from_millis(value)
}

/// 10 per second, three back to back.
fn policy() -> GcraPolicy {
    let burst = NonZeroU64::new(3).unwrap();
    GcraPolicy::per(Duration::from_secs(1), NonZeroU64::new(10).unwrap(), burst).unwrap()
}

fn limiter() -> KeyedGcra<String> {
    KeyedGcra::new(policy())
}

fn bounded(max_keys: usize) -> KeyedGcra<u32> {
    let max = NonZeroUsize::new(max_keys).unwrap();
    KeyedGcra::with_hasher(policy(), NonZeroUsize::MIN, max, RandomState::new())
        .evict_at(usize::MAX)
}

#[test]
fn keys_are_limited_independently() {
    let limiter = limiter();
    let admitted = |key: &str| {
        (0..4)
            .map(|_| limiter.check(key, ms(1000)))
            .collect::<Vec<_>>()
    };
    let expected = [Ok(2), Ok(1), Ok(0), Err(Refusal::Throttled)];
    assert_eq!(admitted("alice"), expected);
    assert_eq!(admitted("bob"), expected);
    assert_eq!(limiter.len(), 2);
    assert_eq!(limiter.policy(), policy());
}

#[test]
fn a_refusal_keeps_the_tat_and_reports_retry_after() {
    let limiter = limiter();
    for _ in 0..3 {
        limiter.check("alice", ms(1000)).unwrap();
    }
    assert_eq!(limiter.check("alice", ms(1000)), Err(Refusal::Throttled));
    let wait = limiter.retry_after("alice", ms(1000));
    assert_eq!(wait, ms(100));
    assert_eq!(limiter.check("alice", ms(1000) + wait), Ok(0));
}

#[test]
fn peek_does_not_consume_or_track() {
    let limiter = limiter();
    assert_eq!(limiter.peek("alice", ms(1000)), Ok(3));
    assert!(limiter.is_empty());
    for _ in 0..3 {
        limiter.check("alice", ms(1000)).unwrap();
    }
    assert_eq!(limiter.peek("alice", ms(1000)), Err(Refusal::Throttled));
    assert_eq!(limiter.peek("alice", ms(1100)), Ok(1));
    assert_eq!(limiter.check("alice", ms(1100)), Ok(0));
    assert_eq!(limiter.retry_after("nobody", ms(1100)), Duration::ZERO);
}

#[test]
fn evicts_only_recovered_keys() {
    let limiter = limiter();
    limiter.check("idle", ms(1000)).unwrap(); // TAT 1.1 s
    limiter.check("busy", ms(2000)).unwrap(); // TAT 2.1 s
    assert_eq!(limiter.evict(ms(2000)), 1);
    assert_eq!(limiter.len(), 1);
    assert_eq!(
        limiter.peek("idle", ms(2000)),
        Ok(3),
        "evicted keys start fresh"
    );
    assert_eq!(limiter.evict(ms(2100)), 1);
    assert!(limiter.is_empty());
}

#[test]
fn admissions_sweep_a_shard_past_the_threshold() {
    let limiter = KeyedGcra::<u32>::with_hasher(
        policy(),
        NonZeroUsize::MIN,
        NonZeroUsize::new(64).unwrap(),
        RandomState::new(),
    )
    .evict_at(2);
    limiter.check(&1, Duration::ZERO).unwrap();
    limiter.check(&2, Duration::ZERO).unwrap();
    // Both earlier keys have recovered by 1 s, so the third admission sweeps them.
    limiter.check(&3, ms(1000)).unwrap();
    assert_eq!(limiter.len(), 1);
}

#[test]
fn an_identity_spray_cannot_pass_the_cap_or_reset_tracked_keys() {
    let limiter = bounded(2);
    for _ in 0..3 {
        limiter.check(&1, ms(1000)).unwrap();
    }
    limiter.check(&2, ms(1000)).unwrap();
    for key in 3..1000 {
        assert_eq!(limiter.check(&key, ms(1000)), Err(Refusal::Full));
        assert_eq!(limiter.peek(&key, ms(1000)), Err(Refusal::Full));
        assert!(limiter.retry_after(&key, ms(1000)) > Duration::ZERO);
    }
    assert_eq!(limiter.len(), 2);
    assert_eq!(limiter.check(&1, ms(1000)), Err(Refusal::Throttled));
    assert_eq!(limiter.check(&2, ms(1000)), Ok(1), "key 2 keeps its burst");
}

#[test]
fn a_full_shard_reclaims_recovered_keys_before_refusing() {
    let limiter = bounded(1);
    limiter.check(&1, ms(1000)).unwrap();
    assert_eq!(limiter.check(&2, ms(1050)), Err(Refusal::Full));
    assert_eq!(
        limiter.peek(&2, ms(1100)),
        Ok(3),
        "peek sees the slot check would free"
    );
    assert_eq!(limiter.len(), 1, "peek reclaims nothing");
    assert_eq!(limiter.check(&2, ms(1100)), Ok(2));
    assert_eq!(limiter.len(), 1);
}

#[test]
fn concurrent_admissions_cannot_overrun_the_cap() {
    let limiter = bounded(17);
    let barrier = std::sync::Barrier::new(8);
    let admitted: usize = thread::scope(|scope| {
        let handles: Vec<_> = (0..8)
            .map(|worker| {
                let (limiter, barrier) = (&limiter, &barrier);
                scope.spawn(move || {
                    barrier.wait();
                    (0..64)
                        .filter(|key| limiter.check(&(worker * 64 + key), ms(1000)).is_ok())
                        .count()
                })
            })
            .collect();
        handles
            .into_iter()
            .map(|handle| handle.join().expect("admission thread"))
            .sum()
    });
    assert_eq!(admitted, 17);
    assert_eq!(limiter.evict(ms(2000)), 17);
    assert!(limiter.is_empty());
}

#[test]
fn a_refund_undoes_one_admission() {
    let limiter = limiter();
    for _ in 0..3 {
        limiter.check("alice", ms(1000)).unwrap();
    }
    limiter.refund("alice", ms(1000));
    assert_eq!(limiter.check("alice", ms(1000)), Ok(0));
    assert_eq!(limiter.check("alice", ms(1000)), Err(Refusal::Throttled));
}

#[test]
fn refunding_a_new_key_frees_its_slot() {
    let limiter = bounded(1);
    limiter.check(&1, ms(1000)).unwrap();
    limiter.refund(&1, ms(1000));
    assert!(limiter.is_empty());
    assert_eq!(limiter.check(&2, ms(1000)), Ok(2), "the slot went back");
    limiter.refund(&3, ms(1000));
    assert_eq!(limiter.len(), 1, "an untracked key has nothing to refund");
}

#[test]
fn a_full_shard_sweeps_in_batches() {
    let limiter = bounded(16);
    for key in 0..16 {
        limiter.check(&key, ms(u64::from(key) * 10)).unwrap();
    }
    // TATs run 100 to 250 ms; at 100 ms only key 0 has recovered, too few for
    // a batch of two, so the first sweep schedules the next for when key 1
    // recovers and refuses meanwhile.
    assert_eq!(limiter.check(&100, ms(50)), Err(Refusal::Full));
    assert_eq!(limiter.check(&101, ms(100)), Err(Refusal::Full));
    assert_eq!(limiter.retry_after(&101, ms(100)), ms(10));
    assert_eq!(limiter.len(), 16);
    assert_eq!(limiter.check(&102, ms(110)), Ok(2));
    assert_eq!(limiter.len(), 15, "keys 0 and 1 reclaimed together");
}

#[test]
fn evict_reclaims_every_recovered_key_whatever_the_schedule() {
    let limiter = bounded(16);
    for key in 0..16 {
        limiter.check(&key, ms(u64::from(key) * 10)).unwrap();
    }
    assert_eq!(limiter.check(&100, ms(50)), Err(Refusal::Full));
    assert_eq!(limiter.evict(ms(100)), 1);
    assert_eq!(limiter.len(), 15);
}

#[test]
fn an_admission_past_the_end_of_time_tracks_nothing() {
    // Was: the TAT saturated at Duration::MAX and the key was admitted.
    let limiter = limiter();
    let end = Duration::MAX.saturating_sub(ms(50));
    assert_eq!(limiter.peek("alice", end), Err(Refusal::Overflow));
    assert_eq!(limiter.check("alice", end), Err(Refusal::Overflow));
    assert!(limiter.is_empty());
    assert_eq!(limiter.retry_after("alice", end), Duration::MAX);
}
