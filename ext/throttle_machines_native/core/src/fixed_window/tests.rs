use super::*;
use crate::test_support::{allowed, denied};

const LIMIT10_60S: FixedWindowParams = FixedWindowParams {
    window_size: 60.0,
    limit: 10,
};

const fn window(count: u64, window_start: f64) -> FixedWindowState {
    FixedWindowState {
        count,
        window_start,
    }
}

#[test]
fn check_decisions() {
    // (before, now, expected)
    let cases = [
        (window(0, 0.0), 1.0, allowed(window(1, 0.0))),
        (window(10, 0.0), 30.0, denied(window(10, 0.0), 30.0)),
        (window(10, 0.0), 61.0, allowed(window(1, 61.0))),
    ];

    for (before, now, expected) in cases {
        let decision = FixedWindow::check(before, now, LIMIT10_60S);
        assert_eq!(decision, expected, "{before:?} at {now}");
    }
}

#[test]
fn peek_does_not_increment() {
    // (before, now, expected)
    let cases = [
        (window(5, 0.0), 30.0, allowed(window(5, 0.0))),
        (window(10, 0.0), 61.0, allowed(window(0, 61.0))),
    ];

    for (before, now, expected) in cases {
        let decision = FixedWindow::peek(before, now, LIMIT10_60S);
        assert_eq!(decision, expected, "{before:?} at {now}");
    }
}

#[test]
fn remaining_saturates_at_zero() {
    for (count, limit, expected) in [(0, 10, 10), (5, 10, 5), (10, 10, 0), (15, 10, 0)] {
        let remaining = FixedWindow::remaining(count, limit);
        assert_eq!(remaining, expected, "count {count}, limit {limit}");
    }
}
