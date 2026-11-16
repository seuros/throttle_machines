use core::num::NonZeroU64;
use core::time::Duration;

use matryona_machines::testing::refuses;

use super::*;

const fn ms(value: u64) -> Duration {
    Duration::from_millis(value)
}

fn nz(value: u64) -> NonZeroU64 {
    NonZeroU64::new(value).unwrap()
}

/// Five tokens, one more every 100 ms.
fn bucket() -> TokenBucket {
    TokenBucket::new(TokenBucketPolicy::new(nz(5), ms(100)).unwrap())
}

#[test]
fn a_zero_refill_is_no_policy() {
    assert_eq!(TokenBucketPolicy::new(nz(1), Duration::ZERO), None);
    assert_eq!(TokenBucketPolicy::per(Duration::ZERO, nz(2)), None);
}

#[test]
fn a_new_bucket_is_full_and_spends_one_token_per_admission() {
    let mut bucket = bucket();
    assert_eq!(bucket.tokens(), 5);
    let now = ms(1000);
    for left in (0..5).rev() {
        assert_eq!(bucket.check(now), Ok(left));
    }
    refuses(&mut bucket, Refusal::Throttled, |bucket| bucket.check(now));
    assert_eq!(bucket.retry_after(now), ms(100));
}

#[test]
fn a_token_due_exactly_now_is_admitted() {
    let mut bucket = bucket();
    let start = Duration::from_secs(1_700_000_000);
    for _ in 0..5 {
        bucket.check(start).unwrap();
    }
    for step in 1..=50 {
        assert_eq!(bucket.check(start + ms(100) * step), Ok(0), "step {step}");
    }
}

#[test]
fn partial_refill_credit_is_kept() {
    let mut bucket = bucket();
    for _ in 0..5 {
        bucket.check(ms(1000)).unwrap();
    }
    assert_eq!(bucket.check(ms(1150)), Ok(0));
    assert_eq!(bucket.refilled_at(), ms(1100));
    assert_eq!(bucket.retry_after(ms(1150)), ms(50));
    assert_eq!(bucket.check(ms(1200)), Ok(0));
}

#[test]
fn a_full_bucket_banks_nothing() {
    let mut bucket = bucket();
    assert_eq!(bucket.peek(Duration::from_secs(1000)), Ok(5));
    bucket.check(Duration::from_secs(1000)).unwrap();
    assert_eq!(bucket.refilled_at(), Duration::from_secs(1000));
    assert_eq!(bucket.peek(Duration::from_secs(5000)), Ok(5));
}

#[test]
fn peek_answers_what_check_would_without_consuming() {
    let mut bucket = bucket();
    for _ in 0..5 {
        bucket.check(ms(1000)).unwrap();
    }
    let before = bucket;
    assert_eq!(bucket.peek(ms(1050)), Err(Refusal::Throttled));
    assert_eq!(bucket.peek(ms(1250)), Ok(2));
    assert_eq!(bucket, before);
}

#[test]
fn an_earlier_instant_earns_nothing() {
    let mut bucket = bucket();
    for _ in 0..5 {
        bucket.check(ms(1000)).unwrap();
    }
    refuses(&mut bucket, Refusal::Throttled, |bucket| {
        bucket.check(ms(10))
    });
    assert_eq!(bucket.retry_after(ms(10)), ms(1090));
}

#[test]
fn a_refund_puts_one_token_back_up_to_capacity() {
    let mut bucket = bucket();
    bucket.check(ms(1000)).unwrap();
    bucket.refund();
    assert_eq!(bucket.tokens(), 5);
    bucket.refund();
    assert_eq!(bucket.tokens(), 5);
}

#[test]
fn restored_refuses_more_tokens_than_capacity() {
    let policy = TokenBucketPolicy::new(nz(2), ms(10)).unwrap();
    assert_eq!(TokenBucket::restored(policy, 3, Duration::ZERO), None);
    let bucket = TokenBucket::restored(policy, 0, ms(5)).unwrap();
    assert_eq!(bucket.policy(), policy);
    assert_eq!(bucket.peek(ms(15)), Ok(1));
}

#[test]
fn per_spreads_the_limit_over_the_period() {
    let policy = TokenBucketPolicy::per(Duration::from_secs(1), nz(3)).unwrap();
    assert_eq!(policy.capacity(), nz(3));
    assert_eq!(policy.refill_every(), Duration::from_nanos(333_333_334));
}

#[test]
fn a_token_due_past_the_end_of_time_is_never_due() {
    // Was: the deadline saturated at Duration::MAX, so retry_after named an
    // instant at which check still refused.
    let policy = TokenBucketPolicy::new(nz(1), Duration::from_secs(2)).unwrap();
    let start = Duration::MAX.saturating_sub(Duration::from_secs(1));
    let mut bucket = TokenBucket::restored(policy, 0, start).unwrap();
    assert_eq!(bucket.retry_after(start), Duration::MAX);
    refuses(&mut bucket, Refusal::Throttled, |bucket| {
        bucket.check(Duration::MAX)
    });
}
