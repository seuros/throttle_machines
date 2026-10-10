use super::*;
use crate::test_support::{allowed, denied};

const NO_BURST: GcraParams = GcraParams {
    emission_interval: 0.1,
    delay_tolerance: 0.0,
};
/// Tolerance 0.25 at interval 0.1: three requests burst before limiting.
const BURST3: GcraParams = GcraParams {
    emission_interval: 0.1,
    delay_tolerance: 0.25,
};

/// Run successive `check`s from a zero TAT and return each admission. Every
/// admission must carry a zero `retry_after` and every refusal a positive one.
fn admissions<const N: usize>(params: GcraParams, times: [f64; N]) -> [bool; N] {
    let mut tat = 0.0;
    times.map(|now| {
        let decision = Gcra::check(tat, now, params);
        assert_eq!(
            decision.retry_after > 0.0,
            !decision.allowed,
            "{decision:?}"
        );
        tat = decision.state;
        decision.allowed
    })
}

#[test]
fn first_request_advances_tat() {
    assert_eq!(Gcra::check(0.0, 1.0, NO_BURST), allowed(1.0 + 0.1));
}

#[test]
fn successive_checks() {
    assert_eq!(admissions(NO_BURST, [1.0, 1.0]), [true, false], "too fast");
    assert_eq!(
        admissions(NO_BURST, [1.0, 1.15]),
        [true, true],
        "after the interval"
    );
    // The fourth request's diff (~0.3) exceeds the 0.25 tolerance.
    assert_eq!(
        admissions(BURST3, [1.0; 4]),
        [true, true, true, false],
        "burst"
    );
}

#[test]
fn peek_does_not_advance_tat() {
    // (tat, now, expected)
    let cases = [(0.0, 1.0, allowed(1.0)), (1.5, 1.0, denied(1.5, 0.5))];

    for (tat, now, expected) in cases {
        assert_eq!(
            Gcra::peek(tat, now, NO_BURST),
            expected,
            "tat {tat} at {now}"
        );
    }
}
