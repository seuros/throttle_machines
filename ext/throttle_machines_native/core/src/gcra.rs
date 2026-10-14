//! Generic Cell Rate Algorithm (GCRA): smooth rate limiting via a Theoretical
//! Arrival Time (TAT) advanced by an emission interval per request.

use crate::gate::{Decision, Gate, rounding_slack};

/// GCRA configuration.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GcraParams {
    /// Time between allowed requests (period / limit).
    pub emission_interval: f64,
    /// Extra time allowed for bursting (0 for none).
    pub delay_tolerance: f64,
}

impl GcraParams {
    /// `per_second` sustained, with `burst` back-to-back requests allowed from
    /// idle (`0` and `1` both mean no burst).
    ///
    /// ```
    /// use throttle_machines::gcra::GcraParams;
    /// let params = GcraParams::from_rate(10.0, 3);
    /// assert_eq!(params.emission_interval, 0.1);
    /// assert_eq!(params.delay_tolerance, 0.2);
    /// ```
    #[must_use]
    pub fn from_rate(per_second: f64, burst: u32) -> Self {
        let emission_interval = per_second.recip();
        Self {
            emission_interval,
            delay_tolerance: f64::from(burst.saturating_sub(1)) * emission_interval,
        }
    }
}

/// GCRA gate. State is the TAT (`0.0` for the first request).
pub struct Gcra;

/// Whether `tat` is within `delay_tolerance` of `now`, allowing for the
/// rounding a running sum of emission intervals accumulates.
#[inline]
fn within_tolerance(tat: f64, now: f64, delay_tolerance: f64) -> bool {
    tat - now <= delay_tolerance + rounding_slack(tat)
}

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

        if within_tolerance(new_tat, now, params.delay_tolerance) {
            Decision {
                allowed: true,
                state: new_tat + params.emission_interval,
                retry_after: 0.0,
            }
        } else {
            Decision {
                allowed: false,
                state: new_tat,
                retry_after: new_tat - now - params.delay_tolerance,
            }
        }
    }

    #[inline]
    fn peek(tat: f64, now: f64, params: GcraParams) -> Decision<f64> {
        let effective_tat = tat.max(now);
        let allowed = within_tolerance(effective_tat, now, params.delay_tolerance);

        Decision {
            allowed,
            state: effective_tat,
            retry_after: if allowed {
                0.0
            } else {
                effective_tat - now - params.delay_tolerance
            },
        }
    }
}

#[cfg(test)]
mod tests;
