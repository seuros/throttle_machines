use super::*;
use crate::test_support::{allowed, denied};
use CircuitState::{Closed, HalfOpen, Open};

const RESET30: BreakerParams = BreakerParams {
    reset_timeout: 30.0,
};
const THRESHOLD: u32 = 3;

const CLOSED: BreakerState = breaker(Closed, 0.0);
const OPEN: BreakerState = breaker(Open, 10.0);
const HALF_OPEN: BreakerState = breaker(HalfOpen, 10.0);

const fn breaker(state: CircuitState, opened_at: f64) -> BreakerState {
    BreakerState { state, opened_at }
}

const fn outcome(new_state: CircuitState, new_failures: u32, opened_at: f64) -> RecordResult {
    RecordResult {
        new_state,
        new_failures,
        opened_at,
    }
}

#[test]
fn state_u8_roundtrip() {
    for state in [Closed, Open, HalfOpen] {
        assert_eq!(CircuitState::try_from(state.to_u8()), Ok(state));
        assert_eq!(CircuitState::from_u8(state.to_u8()), state);
    }
}

#[test]
fn unknown_state_encodings() {
    for value in [3, 99, u8::MAX] {
        let strict = CircuitState::try_from(value);
        assert_eq!(strict, Err(InvalidCircuitState(value)));
        // The lossy decode keeps failing open.
        assert_eq!(CircuitState::from_u8(value), Closed, "value: {value}");
    }
}

#[test]
fn invalid_state_error_message() {
    extern crate std;
    use std::string::ToString;

    assert_eq!(
        InvalidCircuitState(7).to_string(),
        "invalid circuit state encoding 7 (expected 0, 1 or 2)"
    );
}

#[test]
fn check_decisions() {
    // (before, now, expected); `OPEN` cools down until 40.0.
    let cases = [
        (CLOSED, 1.0, allowed(CLOSED)),
        (OPEN, 20.0, denied(OPEN, 20.0)),
        (OPEN, 41.0, allowed(HALF_OPEN)),
    ];

    for (before, now, expected) in cases {
        let decision = CircuitBreaker::check(before, now, RESET30);
        assert_eq!(decision, expected, "{before:?} at {now}");
    }
}

#[test]
fn peek_never_leaves_open() {
    // (before, now, expected): same admission as `check`, state untouched.
    let cases = [
        (OPEN, 20.0, denied(OPEN, 20.0)),
        (OPEN, 41.0, allowed(OPEN)),
    ];

    for (before, now, expected) in cases {
        let decision = CircuitBreaker::peek(before, now, RESET30);
        assert_eq!(decision, expected, "{before:?} at {now}");
    }
}

#[test]
fn record_outcomes() {
    // ((state, failures, now, success), expected)
    let cases = [
        // Failures below the threshold only count.
        ((Closed, 0, 1.0, false), outcome(Closed, 1, 0.0)),
        ((Closed, 1, 2.0, false), outcome(Closed, 2, 0.0)),
        // Reaching it trips at `now`; the count saturates instead of wrapping.
        ((Closed, 2, 3.0, false), outcome(Open, 3, 3.0)),
        ((Closed, u32::MAX, 4.0, false), outcome(Open, u32::MAX, 4.0)),
        // Success always closes and resets.
        ((Closed, 2, 5.0, true), outcome(Closed, 0, 0.0)),
        ((HalfOpen, 3, 50.0, true), outcome(Closed, 0, 0.0)),
        // A failed probe, or any failure while open, re-trips at `now`.
        ((HalfOpen, 3, 50.0, false), outcome(Open, 3, 50.0)),
        ((Open, 3, 60.0, false), outcome(Open, 3, 60.0)),
    ];

    for ((state, failures, now, success), expected) in cases {
        let result = CircuitBreaker::record(state, failures, now, success, THRESHOLD);
        assert_eq!(
            result, expected,
            "{state:?}, {failures} failures, success {success}"
        );
    }
}
