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
            retry_after: if allowed {
                0.0
            } else {
                diff - params.delay_tolerance
            },
        }
    }
}

#[cfg(test)]
mod tests;
