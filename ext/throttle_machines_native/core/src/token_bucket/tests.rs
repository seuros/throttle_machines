use super::*;
use crate::test_support::{allowed, denied};

const CAP10_RATE1: TokenBucketParams = TokenBucketParams {
    capacity: 10.0,
    refill_rate: 1.0,
};
const CAP10_RATE2: TokenBucketParams = TokenBucketParams {
    capacity: 10.0,
    refill_rate: 2.0,
};

const fn bucket(tokens: f64, last_refill: f64) -> TokenBucketState {
    TokenBucketState {
        tokens,
        last_refill,
    }
}

#[test]
fn allows_and_consumes_one_token() {
    // (case, bucket before, now, tokens after)
    let cases = [
        ("full bucket", bucket(10.0, 0.0), 1.0, 9.0),
        ("refills over time", bucket(0.0, 0.0), 5.0, 4.0),
        ("refill capped at capacity", bucket(10.0, 0.0), 100.0, 9.0),
        ("partial bucket", bucket(5.0, 0.0), 1.0, 5.0),
    ];

    for (case, before, now, tokens) in cases {
        let decision = TokenBucket::check(before, now, CAP10_RATE1);
        assert_eq!(decision, allowed(bucket(tokens, now)), "{case}");
        // Pure, so `peek` reports the same hypothetical consume.
        let peeked = TokenBucket::peek(before, now, CAP10_RATE1);
        assert_eq!(peeked, decision, "{case}: peek");
    }
}

#[test]
fn denies_until_next_token() {
    // (case, bucket before, now, params, retry_after)
    let cases = [
        ("empty bucket", bucket(0.0, 0.0), 0.0, CAP10_RATE1, 1.0),
        (
            "half a token short",
            bucket(0.5, 1.0),
            1.0,
            CAP10_RATE2,
            0.25,
        ),
    ];

    for (case, before, now, params, retry_after) in cases {
        let decision = TokenBucket::check(before, now, params);
        assert_eq!(
            decision,
            denied(bucket(before.tokens, now), retry_after),
            "{case}"
        );
    }
}

#[test]
fn token_due_now_survives_float_rounding() {
    // `(start + 0.1) - start` is a hair under 0.1 at large clock readings, so
    // the refill lands just short of one token.
    let params = TokenBucketParams {
        capacity: 3.0,
        refill_rate: 10.0,
    };
    for start in [1.0, 12_345.678, 1_700_000_000.0] {
        let drained = bucket(0.0, start);
        let decision = TokenBucket::check(drained, start + 0.1, params);
        assert!(decision.allowed, "start {start}: {decision:?}");
        assert!(decision.state.tokens >= 0.0, "start {start}: {decision:?}");
        // Still refused well before the token is due.
        assert!(
            !TokenBucket::check(drained, start + 0.09, params).allowed,
            "start {start}"
        );
    }
}
