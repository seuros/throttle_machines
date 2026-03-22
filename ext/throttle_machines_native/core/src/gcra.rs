//! Generic Cell Rate Algorithm (GCRA) implementation.
//!
//! GCRA provides smooth, precise rate limiting by tracking a "Theoretical Arrival Time" (TAT).
//! Each request advances the TAT by an emission interval, and requests are allowed
//! only if the current time is close enough to the TAT.

/// Result of a GCRA rate limit check.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GcraResult {
    /// Whether the request is allowed.
    pub allowed: bool,
    /// The new Theoretical Arrival Time after this check.
    pub new_tat: f64,
    /// Seconds until the next request would be allowed (0 if allowed).
    pub retry_after: f64,
}

/// Check if a request is allowed under GCRA.
///
/// # Arguments
///
/// * `tat` - Current Theoretical Arrival Time (0.0 for first request)
/// * `now` - Current timestamp in seconds
/// * `emission_interval` - Time between allowed requests (period / limit)
/// * `delay_tolerance` - Extra time allowed for bursting (0 for no burst)
///
/// # Returns
///
/// A `GcraResult` indicating whether the request is allowed and the new TAT.
///
/// # Example
///
/// ```
/// use throttle_machines::gcra;
///
/// // Allow 10 requests per second (emission_interval = 0.1)
/// let result = gcra::check(0.0, 1.0, 0.1, 0.0);
/// assert!(result.allowed);
/// ```
#[inline]
pub fn check(tat: f64, now: f64, emission_interval: f64, delay_tolerance: f64) -> GcraResult {
    // TAT should be at least `now` (can't be in the past)
    let new_tat = if tat > now { tat } else { now };

    // How far ahead is the TAT from now?
    let diff = new_tat - now;

    // Allow if we're within the tolerance window
    let allowed = diff <= delay_tolerance;

    if allowed {
        GcraResult {
            allowed: true,
            new_tat: new_tat + emission_interval,
            retry_after: 0.0,
        }
    } else {
        GcraResult {
            allowed: false,
            new_tat,
            retry_after: diff - delay_tolerance,
        }
    }
}

/// Peek at the current state without consuming a request.
///
/// This is useful for checking remaining capacity without modifying state.
#[inline]
pub fn peek(tat: f64, now: f64, delay_tolerance: f64) -> GcraResult {
    let effective_tat = if tat > now { tat } else { now };
    let diff = effective_tat - now;
    let allowed = diff <= delay_tolerance;

    GcraResult {
        allowed,
        new_tat: effective_tat,
        retry_after: if allowed { 0.0 } else { diff - delay_tolerance },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_first_request_allowed() {
        let result = check(0.0, 1.0, 0.1, 0.0);
        assert!(result.allowed);
        assert!((result.new_tat - 1.1).abs() < 0.0001);
        assert_eq!(result.retry_after, 0.0);
    }

    #[test]
    fn test_rate_limited_when_too_fast() {
        // First request at t=1.0
        let r1 = check(0.0, 1.0, 0.1, 0.0);
        assert!(r1.allowed);

        // Second request immediately at t=1.0 (too fast)
        let r2 = check(r1.new_tat, 1.0, 0.1, 0.0);
        assert!(!r2.allowed);
        assert!(r2.retry_after > 0.0);
    }

    #[test]
    fn test_allowed_after_waiting() {
        // First request
        let r1 = check(0.0, 1.0, 0.1, 0.0);

        // Second request after waiting
        let r2 = check(r1.new_tat, 1.15, 0.1, 0.0);
        assert!(r2.allowed);
    }

    #[test]
    fn test_burst_with_delay_tolerance() {
        // With delay_tolerance of 0.25 and emission_interval of 0.1,
        // we can allow 3 bursts before being rate limited.
        // Using 0.25 instead of 0.2 to avoid floating point edge cases.
        let r1 = check(0.0, 1.0, 0.1, 0.25);
        assert!(r1.allowed);

        let r2 = check(r1.new_tat, 1.0, 0.1, 0.25);
        assert!(r2.allowed);

        let r3 = check(r2.new_tat, 1.0, 0.1, 0.25);
        assert!(r3.allowed);

        // Fourth request exceeds burst (diff ~= 0.3 > 0.25)
        let r4 = check(r3.new_tat, 1.0, 0.1, 0.25);
        assert!(!r4.allowed);
    }

    #[test]
    fn test_peek_does_not_modify() {
        let result = peek(0.0, 1.0, 0.0);
        assert!(result.allowed);
        // new_tat should be `now`, not advanced
        assert!((result.new_tat - 1.0).abs() < 0.0001);
    }
}
