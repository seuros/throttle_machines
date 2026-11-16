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

/// 10 per second, no burst.
fn steady() -> Gcra {
    Gcra::new(GcraPolicy::new(ms(100), Duration::ZERO).unwrap())
}

/// 10 per second, three back to back.
fn bursty() -> Gcra {
    Gcra::new(GcraPolicy::per(Duration::from_secs(1), nz(10), nz(3)).unwrap())
}

#[test]
fn a_zero_interval_is_no_policy() {
    assert_eq!(GcraPolicy::new(Duration::ZERO, ms(5)), None);
}

#[test]
fn per_rounds_the_interval_up_and_refuses_a_zero_period() {
    let policy = GcraPolicy::per(Duration::from_nanos(10), nz(3), nz(1)).unwrap();
    assert_eq!(policy.emission_interval(), Duration::from_nanos(4));
    assert_eq!(policy.delay_tolerance(), Duration::ZERO);
    assert_eq!(GcraPolicy::per(Duration::ZERO, nz(3), nz(1)), None);
    assert_eq!(GcraPolicy::per(Duration::MAX, nz(1), nz(3)), None);
}

#[test]
fn the_first_admission_pushes_the_tat_one_interval_past_now() {
    let mut gcra = steady();
    assert_eq!(gcra.check(ms(1000)), Ok(0));
    assert_eq!(gcra.tat(), ms(1100));
}

#[test]
fn a_burst_spends_the_tolerance_then_throttles_without_changing_anything() {
    let mut gcra = bursty();
    let now = ms(1000);
    assert_eq!(gcra.peek(now), Ok(3));
    assert_eq!(gcra.check(now), Ok(2));
    assert_eq!(gcra.check(now), Ok(1));
    assert_eq!(gcra.check(now), Ok(0));
    refuses(&mut gcra, Refusal::Throttled, |gcra| gcra.check(now));
    assert_eq!(gcra.retry_after(now), ms(100));
}

#[test]
fn arriving_exactly_on_schedule_is_admitted() {
    let mut gcra = bursty();
    let start = Duration::from_secs(1_700_000_000);
    for _ in 0..3 {
        gcra.check(start).unwrap();
    }
    for step in 1..=50 {
        assert_eq!(gcra.check(start + ms(100) * step), Ok(0), "step {step}");
    }
}

#[test]
fn peek_answers_what_check_would_without_consuming() {
    let mut gcra = steady();
    assert_eq!(gcra.peek(ms(1000)), Ok(1));
    gcra.check(ms(1000)).unwrap();
    let before = gcra;
    assert_eq!(gcra.peek(ms(1050)), Err(Refusal::Throttled));
    assert_eq!(gcra.peek(ms(1100)), Ok(1));
    assert_eq!(gcra, before);
}

#[test]
fn retry_after_is_zero_when_admitted() {
    let mut gcra = steady();
    assert_eq!(gcra.retry_after(ms(5)), Duration::ZERO);
    gcra.check(ms(1000)).unwrap();
    assert_eq!(gcra.retry_after(ms(1040)), ms(60));
    assert_eq!(gcra.retry_after(ms(2000)), Duration::ZERO);
}

#[test]
fn an_earlier_instant_is_answered_no_more_generously() {
    let mut gcra = steady();
    gcra.check(ms(1000)).unwrap();
    refuses(&mut gcra, Refusal::Throttled, |gcra| gcra.check(ms(500)));
    assert_eq!(gcra.retry_after(ms(500)), ms(600));
}

#[test]
fn a_refund_frees_the_admission_it_undoes() {
    let mut gcra = steady();
    gcra.check(ms(1000)).unwrap();
    gcra.refund();
    assert_eq!(gcra.tat(), ms(1000));
    assert_eq!(gcra.check(ms(1000)), Ok(0));
}

#[test]
fn a_refund_never_reaches_before_the_epoch() {
    let mut gcra = steady();
    gcra.refund();
    assert_eq!(gcra.tat(), Duration::ZERO);
}

#[test]
fn a_restored_limiter_resumes_where_its_tat_left_off() {
    let policy = GcraPolicy::new(ms(100), Duration::ZERO).unwrap();
    let mut gcra = Gcra::restored(policy, ms(1100));
    assert_eq!(gcra.policy(), policy);
    assert_eq!(gcra.check(ms(1050)), Err(Refusal::Throttled));
    assert_eq!(gcra.check(ms(1100)), Ok(0));
}

const fn ns(value: u64) -> Duration {
    Duration::from_nanos(value)
}

/// Admissions `check` grants back to back at `now`, up to `most`.
fn admitted(mut gcra: Gcra, now: Duration, most: u64) -> u64 {
    (0..most).take_while(|_| gcra.check(now).is_ok()).count() as u64
}

#[test]
fn a_burst_ceiling_past_a_duration_is_no_policy() {
    // Was: the ceiling saturated, so after check(1ms) peek(1ms) answered 0
    // although another check(1ms) still admitted.
    assert_eq!(GcraPolicy::new(Duration::MAX, Duration::MAX), None);
    assert_eq!(GcraPolicy::new(Duration::MAX, ns(1)), None);
    assert_eq!(GcraPolicy::new(ns(1), Duration::MAX), None);
    assert!(GcraPolicy::new(Duration::MAX, Duration::ZERO).is_some());
    assert!(GcraPolicy::new(Duration::MAX.saturating_sub(ns(5)), ns(5)).is_some());
    assert_eq!(
        GcraPolicy::per(Duration::MAX, nz(2), nz(3)),
        None,
        "a ceiling of three intervals past Duration::MAX"
    );
}

#[test]
fn a_capacity_past_u64_is_no_policy() {
    // Was: a capacity of 2**64 answered 2**64-1.
    assert_eq!(GcraPolicy::new(ns(1), ns(u64::MAX)), None);
    let widest = Gcra::new(GcraPolicy::new(ns(1), ns(u64::MAX - 1)).unwrap());
    assert_eq!(widest.peek(Duration::ZERO), Ok(u64::MAX));
    let mut spent = widest;
    assert_eq!(spent.check(Duration::ZERO), Ok(u64::MAX - 1));
}

#[test]
fn the_tat_never_saturates_into_extra_admissions() {
    // Was: the TAT saturated at Duration::MAX, which put it back within
    // tolerance, so every later check at `now` was admitted.
    let policy = GcraPolicy::new(Duration::from_secs(1), ms(1500)).unwrap();
    let now = Duration::MAX.saturating_sub(ms(1200));
    let mut gcra = Gcra::new(policy);
    assert_eq!(gcra.peek(now), Ok(1), "one more interval fits");
    assert_eq!(gcra.check(now), Ok(0));
    assert_eq!(gcra.tat(), now + Duration::from_secs(1));
    refuses(&mut gcra, Refusal::Overflow, |gcra| gcra.check(now));
    assert_eq!(gcra.peek(now), Err(Refusal::Overflow));
    assert_eq!(
        gcra.retry_after(now),
        Duration::MAX,
        "no later instant admits"
    );
    refuses(&mut gcra, Refusal::Overflow, |gcra| {
        gcra.check(Duration::MAX)
    });
}

#[test]
fn throttled_comes_before_overflow_and_waits_for_the_tolerance() {
    let policy = GcraPolicy::new(Duration::from_secs(1), Duration::ZERO).unwrap();
    let mut gcra = Gcra::restored(policy, Duration::MAX.saturating_sub(ms(500)));
    let now = Duration::MAX.saturating_sub(Duration::from_secs(3));
    refuses(&mut gcra, Refusal::Throttled, |gcra| gcra.check(now));
    assert_eq!(
        gcra.retry_after(now),
        Duration::MAX,
        "the TAT cannot advance"
    );
    let early = Gcra::restored(policy, Duration::MAX.saturating_sub(Duration::from_secs(2)));
    assert_eq!(early.retry_after(now), Duration::from_secs(1));
}

#[test]
fn peek_counts_exactly_what_check_admits() {
    let policies = [
        (ns(1), Duration::ZERO),
        (ns(3), ns(7)),
        (ms(100), ms(200)),
        (Duration::from_secs(1), ms(1500)),
        (Duration::MAX.saturating_sub(ns(5)), ns(5)),
        (Duration::MAX, Duration::ZERO),
    ];
    let instants = [
        Duration::ZERO,
        ns(2),
        ms(150),
        Duration::MAX.saturating_sub(ms(1200)),
        Duration::MAX.saturating_sub(ns(4)),
        Duration::MAX,
    ];
    for (interval, tolerance) in policies {
        let policy = GcraPolicy::new(interval, tolerance).unwrap();
        for tat in instants {
            for now in instants {
                let gcra = Gcra::restored(policy, tat);
                let expected = admitted(gcra, now, 16);
                match gcra.peek(now) {
                    Ok(count) => assert_eq!(
                        count, expected,
                        "{interval:?} {tolerance:?} {tat:?} {now:?}"
                    ),
                    Err(_) => assert_eq!(expected, 0, "{interval:?} {tolerance:?} {tat:?} {now:?}"),
                }
                let wait = gcra.retry_after(now);
                assert_eq!(
                    wait.is_zero(),
                    expected > 0,
                    "{interval:?} {tolerance:?} {tat:?} {now:?}"
                );
            }
        }
    }
}
