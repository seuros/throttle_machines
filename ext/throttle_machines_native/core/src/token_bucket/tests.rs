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
