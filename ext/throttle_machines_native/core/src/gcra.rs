//! Generic Cell Rate Algorithm (GCRA): smooth rate limiting via a Theoretical
//! Arrival Time (TAT) advanced by an emission interval per request.

use crate::gate::{Decision, Gate};

/// GCRA configuration.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GcraParams {
    /// Time between allowed requests (period / limit).
    pub emission_interval: f64,
    /// Extra time allowed for bursting (0 for none).
    pub delay_tolerance: f64,
}

/// GCRA gate. State is the TAT (`0.0` for the first request).
pub struct Gcra;

impl Gate for Gcra {
    type State = f64;
    type Params = GcraParams;

    /// ```
    /// use throttle_machines::gate::Gate;
    /// use throttle_machines::gcra::{Gcra, GcraParams};
    /// let params = GcraParams { emission_interval: 0.1, delay_tolerance: 0.0 };
    /// assert!(Gcra::check(0.0, 1.0, params).allowed);
    /// ```
    #[inline]
    fn check(tat: f64, now: f64, params: GcraParams) -> Decision<f64> {
        let new_tat = tat.max(now);
        let diff = new_tat - now;

        if diff <= params.delay_tolerance {
            Decision {
                allowed: true,
                state: new_tat + params.emission_interval,
                retry_after: 0.0,
            }
        } else {
            Decision {
                allowed: false,
                state: new_tat,
                retry_after: diff - params.delay_tolerance,
            }
        }
    }

    #[inline]
    fn peek(tat: f64, now: f64, params: GcraParams) -> Decision<f64> {
        let effective_tat = tat.max(now);
        let diff = effective_tat - now;
        let allowed = diff <= params.delay_tolerance;

        Decision {
            allowed,
            state: effective_tat,
            retry_after: if allowed { 0.0 } else { diff - params.delay_tolerance },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NO_BURST: GcraParams = GcraParams {
        emission_interval: 0.1,
        delay_tolerance: 0.0,
    };

    #[test]
    fn test_first_request_allowed() {
        let result = Gcra::check(0.0, 1.0, NO_BURST);
        assert!(result.allowed);
        assert!((result.state - 1.1).abs() < 0.0001);
        assert_eq!(result.retry_after, 0.0);
    }

    #[test]
    fn test_rate_limited_when_too_fast() {
        let r1 = Gcra::check(0.0, 1.0, NO_BURST);
        assert!(r1.allowed);

        // Second request immediately (too fast).
        let r2 = Gcra::check(r1.state, 1.0, NO_BURST);
        assert!(!r2.allowed);
        assert!(r2.retry_after > 0.0);
    }

    #[test]
    fn test_allowed_after_waiting() {
        let r1 = Gcra::check(0.0, 1.0, NO_BURST);
        let r2 = Gcra::check(r1.state, 1.15, NO_BURST);
        assert!(r2.allowed);
    }

    #[test]
    fn test_burst_with_delay_tolerance() {
        // tolerance 0.25, interval 0.1 -> 3 bursts before limiting.
        let burst = GcraParams {
            emission_interval: 0.1,
            delay_tolerance: 0.25,
        };
        let r1 = Gcra::check(0.0, 1.0, burst);
        assert!(r1.allowed);

        let r2 = Gcra::check(r1.state, 1.0, burst);
        assert!(r2.allowed);

        let r3 = Gcra::check(r2.state, 1.0, burst);
        assert!(r3.allowed);

        // Fourth exceeds burst (diff ~= 0.3 > 0.25).
        let r4 = Gcra::check(r3.state, 1.0, burst);
        assert!(!r4.allowed);
    }

    #[test]
    fn test_peek_does_not_modify() {
        let result = Gcra::peek(0.0, 1.0, NO_BURST);
        assert!(result.allowed);
        assert!((result.state - 1.0).abs() < 0.0001);
    }
}
