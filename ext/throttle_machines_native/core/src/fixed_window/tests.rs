use core::num::NonZeroU64;
use core::time::Duration;

use matryona_machines::testing::refuses;

use super::*;

const fn secs(value: u64) -> Duration {
    Duration::from_secs(value)
}

/// Two calls per 60 s.
fn window() -> FixedWindow {
    FixedWindow::new(FixedWindowPolicy::new(secs(60), NonZeroU64::new(2).unwrap()).unwrap())
}

#[test]
fn a_zero_window_is_no_policy() {
    assert_eq!(
        FixedWindowPolicy::new(Duration::ZERO, NonZeroU64::MIN),
        None
    );
}

#[test]
fn counts_up_to_the_limit_then_throttles_without_counting() {
    let mut window = window();
    assert_eq!(window.check(secs(100)), Ok(1));
    assert_eq!(window.window_start(), secs(100));
    assert_eq!(window.check(secs(110)), Ok(0));
    refuses(&mut window, Refusal::Throttled, |window| {
        window.check(secs(120))
    });
    assert_eq!(window.count(), 2);
    assert_eq!(window.retry_after(secs(120)), secs(40));
}

#[test]
fn a_window_that_ended_opens_a_new_one_at_now() {
    let mut window = window();
    window.check(secs(100)).unwrap();
    window.check(secs(100)).unwrap();
    assert_eq!(window.peek(secs(160)), Ok(2));
    assert_eq!(window.check(secs(161)), Ok(1));
    assert_eq!(window.window_start(), secs(161));
}

#[test]
fn peek_does_not_count() {
    let mut window = window();
    assert_eq!(window.peek(secs(1)), Ok(2));
    window.check(secs(1)).unwrap();
    let before = window;
    assert_eq!(window.peek(secs(2)), Ok(1));
    assert_eq!(window, before);
    assert_eq!(window.retry_after(secs(2)), Duration::ZERO);
}

#[test]
fn the_first_window_opens_at_the_epoch() {
    let mut window = window();
    window.check(secs(10)).unwrap();
    assert_eq!(window.window_start(), Duration::ZERO);
}

#[test]
fn a_refund_takes_one_off_the_count() {
    let mut window = window();
    window.check(secs(100)).unwrap();
    window.check(secs(100)).unwrap();
    window.refund();
    assert_eq!(window.check(secs(100)), Ok(0));
    let mut fresh = self::window();
    fresh.refund();
    assert_eq!(fresh.count(), 0);
}

#[test]
fn restored_refuses_a_count_past_the_limit() {
    let policy = FixedWindowPolicy::new(secs(1), NonZeroU64::MIN).unwrap();
    assert_eq!(FixedWindow::restored(policy, 2, Duration::ZERO), None);
    let window = FixedWindow::restored(policy, 1, secs(5)).unwrap();
    assert_eq!(window.policy(), policy);
    assert_eq!(window.peek(secs(5)), Err(Refusal::Throttled));
    assert_eq!(window.peek(secs(6)), Ok(1));
}

#[test]
fn a_window_ending_past_the_end_of_time_never_ends() {
    // Was: the window end saturated at Duration::MAX, so a check at
    // Duration::MAX opened a fresh window inside the current one.
    let policy = FixedWindowPolicy::new(secs(2), NonZeroU64::MIN).unwrap();
    let mut window =
        FixedWindow::restored(policy, 1, Duration::MAX.saturating_sub(secs(1))).unwrap();
    refuses(&mut window, Refusal::Throttled, |window| {
        window.check(Duration::MAX)
    });
    assert_eq!(window.peek(Duration::MAX), Err(Refusal::Throttled));
    assert_eq!(
        window.retry_after(Duration::MAX.saturating_sub(secs(1))),
        Duration::MAX
    );
}
