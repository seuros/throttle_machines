use super::*;

/// Rate 10/s, burst 3.
fn limiter() -> KeyedGcra<String> {
    KeyedGcra::new(GcraParams::from_rate(10.0, 3))
}

#[test]
fn keys_are_limited_independently() {
    let limiter = limiter();
    let admitted = |key: &str| {
        (0..4)
            .map(|_| limiter.check_at(key, 1.0).allowed)
            .collect::<Vec<_>>()
    };

    assert_eq!(admitted("alice"), [true, true, true, false]);
    assert_eq!(admitted("bob"), [true, true, true, false]);
    assert_eq!(limiter.len(), 2);
}

#[test]
fn refusal_keeps_state_and_reports_retry_after() {
    let limiter = limiter();
    for _ in 0..3 {
        limiter.check_at("alice", 1.0);
    }
    let refused = limiter.check_at("alice", 1.0);
    assert!(!refused.allowed);
    assert!((refused.retry_after - 0.1).abs() < 1e-9, "{refused:?}");
    // Arriving exactly when told to is admitted.
    assert!(limiter.check_at("alice", 1.0 + refused.retry_after).allowed);
}

#[test]
fn peek_does_not_consume_or_track() {
    let limiter = limiter();
    assert!(limiter.peek_at("alice", 1.0).allowed);
    assert!(limiter.is_empty());

    for _ in 0..3 {
        limiter.check_at("alice", 1.0);
    }
    assert!(!limiter.peek_at("alice", 1.0).allowed);
    // Peeking twice changes nothing; the next check agrees with it.
    assert!(limiter.peek_at("alice", 1.1).allowed);
    assert!(limiter.check_at("alice", 1.1).allowed);
    assert!(!limiter.peek_at("alice", 1.1).allowed);
}

#[test]
fn evicts_only_recovered_keys() {
    let limiter = limiter();
    limiter.check_at("idle", 1.0); // TAT 1.1
    limiter.check_at("busy", 2.0); // TAT 2.1

    assert_eq!(limiter.evict_before(2.0), 1);
    assert_eq!(limiter.len(), 1);
    assert!(
        limiter.peek_at("idle", 2.0).allowed,
        "an evicted key starts fresh"
    );
    assert_eq!(limiter.evict_before(2.1), 1);
    assert!(limiter.is_empty());
}

#[test]
fn admissions_sweep_a_shard_past_the_threshold() {
    let limiter =
        KeyedGcra::<u32>::with_hasher(limiter().params(), NonZeroUsize::MIN, RandomState::new())
            .evict_at(2);
    limiter.check_at(&1, 0.0);
    limiter.check_at(&2, 0.0);
    // Both earlier keys have recovered by t=1, so the third insert sweeps them.
    limiter.check_at(&3, 1.0);
    assert_eq!(limiter.len(), 1);
}

#[test]
fn uses_a_monotonic_clock_from_creation() {
    let limiter = limiter();
    let now = limiter.now();
    assert!((0.0..1.0).contains(&now), "{now}");
    assert!(limiter.check("alice").allowed);
    assert!(limiter.now() >= now);
}

fn bounded(max_keys: usize) -> KeyedGcra<u32> {
    KeyedGcra::with_hasher(limiter().params(), NonZeroUsize::MIN, RandomState::new())
        .max_keys_per_shard(max_keys)
        .evict_at(usize::MAX)
}

#[test]
fn identity_spray_cannot_exceed_cap_or_reset_existing_keys() {
    let limiter = bounded(2);
    for _ in 0..3 {
        assert!(limiter.check_at(&1, 1.0).allowed);
    }
    assert!(limiter.check_at(&2, 1.0).allowed);
    for key in 3..1000 {
        let refusal = limiter.check_at(&key, 1.0);
        assert!(!refusal.allowed);
        assert!(refusal.retry_after > 0.0);
        assert_eq!(refusal.state, 0.0);
        assert!(!limiter.peek_at(&key, 1.0).allowed);
    }
    assert_eq!(limiter.len(), 2);
    assert!(!limiter.check_at(&1, 1.0).allowed);
    // Key 2 still has burst capacity even though the store is full.
    assert!(limiter.check_at(&2, 1.0).allowed);
}

#[test]
fn full_shard_reclaims_recovered_keys_before_refusing() {
    let limiter = bounded(1);
    assert!(limiter.check_at(&1, 1.0).allowed);
    assert!(!limiter.check_at(&2, 1.05).allowed);
    assert!(limiter.check_at(&2, 1.1).allowed);
    assert_eq!(limiter.len(), 1);
    assert!(!limiter.peek_at(&1, 1.1).allowed);
    assert!(limiter.peek_at(&1, 2.0).allowed);
    assert!(limiter.is_empty(), "peek only reclaims recovered state");
}

#[test]
fn zero_cap_never_tracks_or_admits_keys() {
    let limiter = bounded(0);
    assert!(!limiter.check_at(&1, 1.0).allowed);
    assert!(!limiter.peek_at(&1, 1.0).allowed);
    assert!(limiter.is_empty());
}

#[test]
fn concurrent_admissions_cannot_overrun_cap() {
    let limiter = bounded(17);
    let barrier = std::sync::Barrier::new(8);
    let admitted: usize = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..8)
            .map(|worker| {
                let limiter = &limiter;
                let barrier = &barrier;
                scope.spawn(move || {
                    barrier.wait();
                    (0..64)
                        .filter(|key| limiter.check_at(&(worker * 64 + key), 1.0).allowed)
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
    assert_eq!(limiter.len(), 17);
    assert_eq!(limiter.evict_before(2.0), 17);
    assert!(limiter.is_empty());
}

#[test]
#[should_panic(expected = "max_keys cannot be smaller than an existing shard")]
fn lowering_cap_cannot_silently_violate_bound() {
    let limiter = bounded(2);
    limiter.check_at(&1, 1.0);
    let _limiter = limiter.max_keys_per_shard(0);
}
