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
