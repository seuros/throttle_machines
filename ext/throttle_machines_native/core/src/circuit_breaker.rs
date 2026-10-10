//! Circuit breaker: an admission gate driven by dependency health.
//!
//! `check`/`peek` are the [`Gate`] decision; [`CircuitBreaker::record`] folds a
//! call outcome back into the state — the breaker's one operation a rate limiter
//! has no analog for.
//!
//! `Closed -> Open` (failures reach threshold), `Open -> HalfOpen` (cooldown
//! elapses, one probe), `HalfOpen -> Closed` (probe ok) / `-> Open` (probe fails).

use core::fmt;

use crate::gate::{Decision, Gate};

/// Circuit state. FFI encoding: `Closed = 0`, `Open = 1`, `HalfOpen = 2`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    /// Calls flow; failures count toward the threshold.
    Closed,
    /// Calls rejected until the reset timeout elapses.
    Open,
    /// One probe allowed to test recovery.
    HalfOpen,
}

impl CircuitState {
    /// Encode as a stable `u8` for the FFI boundary.
    #[inline]
    #[must_use]
    pub const fn to_u8(self) -> u8 {
        match self {
            Self::Closed => 0,
            Self::Open => 1,
            Self::HalfOpen => 2,
        }
    }

    /// Decode from `u8`; unknown values fail open to `Closed`. Use
    /// [`CircuitState::try_from`] to reject them instead.
    #[inline]
    #[must_use]
    pub fn from_u8(value: u8) -> Self {
        Self::try_from(value).unwrap_or(Self::Closed)
    }
}

impl TryFrom<u8> for CircuitState {
    type Error = InvalidCircuitState;

    /// Strict decode of the FFI encoding: unknown values are an error.
    #[inline]
    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Closed),
            1 => Ok(Self::Open),
            2 => Ok(Self::HalfOpen),
            _ => Err(InvalidCircuitState(value)),
        }
    }
}

/// A `u8` that is not a [`CircuitState`] encoding, from
/// [`CircuitState::try_from`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InvalidCircuitState(pub u8);

impl fmt::Display for InvalidCircuitState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "invalid circuit state encoding {} (expected 0, 1 or 2)",
            self.0
        )
    }
}

impl core::error::Error for InvalidCircuitState {}

/// Breaker state.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BreakerState {
    /// Current circuit state.
    pub state: CircuitState,
    /// When the breaker last tripped Open (unused when Closed).
    pub opened_at: f64,
}

/// Breaker configuration.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BreakerParams {
    /// Cooldown before a probe is allowed, in seconds.
    pub reset_timeout: f64,
}

/// Result of [`CircuitBreaker::record`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RecordResult {
    /// State after recording the outcome.
    pub new_state: CircuitState,
    /// Consecutive-failure count after recording.
    pub new_failures: u32,
    /// Trip time when `new_state` is `Open`, else 0.0; persist only when Open.
    pub opened_at: f64,
}

/// Circuit breaker gate.
pub struct CircuitBreaker;

impl Gate for CircuitBreaker {
    type State = BreakerState;
    type Params = BreakerParams;

    /// Performs the time-based `Open -> HalfOpen` transition; persist the
    /// returned state so concurrent callers see the probe window.
    ///
    /// ```
    /// use throttle_machines::gate::Gate;
    /// use throttle_machines::circuit_breaker::{BreakerParams, BreakerState, CircuitBreaker, CircuitState};
    /// let state = BreakerState { state: CircuitState::Closed, opened_at: 0.0 };
    /// let r = CircuitBreaker::check(state, 1.0, BreakerParams { reset_timeout: 30.0 });
    /// assert!(r.allowed);
    /// ```
    #[inline]
    fn check(state: BreakerState, now: f64, params: BreakerParams) -> Decision<BreakerState> {
        match state.state {
            CircuitState::Closed | CircuitState::HalfOpen => Self::allow(state),
            CircuitState::Open => {
                let elapsed = now - state.opened_at;
                if elapsed >= params.reset_timeout {
                    Decision {
                        allowed: true,
                        state: BreakerState {
                            state: CircuitState::HalfOpen,
                            opened_at: state.opened_at,
                        },
                        retry_after: 0.0,
                    }
                } else {
                    Decision {
                        allowed: false,
                        state,
                        retry_after: params.reset_timeout - elapsed,
                    }
                }
            }
        }
    }

    /// Like `check`, but never transitions `Open -> HalfOpen`.
    #[inline]
    fn peek(state: BreakerState, now: f64, params: BreakerParams) -> Decision<BreakerState> {
        match state.state {
            CircuitState::Closed | CircuitState::HalfOpen => Self::allow(state),
            CircuitState::Open => {
                let remaining = params.reset_timeout - (now - state.opened_at);
                Decision {
                    allowed: remaining <= 0.0,
                    state,
                    retry_after: if remaining > 0.0 { remaining } else { 0.0 },
                }
            }
        }
    }
}

impl CircuitBreaker {
    /// Shared "allowed, state unchanged" decision for Closed/HalfOpen.
    #[inline]
    const fn allow(state: BreakerState) -> Decision<BreakerState> {
        Decision {
            allowed: true,
            state,
            retry_after: 0.0,
        }
    }

    /// Fold a call outcome into the state. Success closes/resets; failure in
    /// `HalfOpen` (or `Open`) re-trips, and in `Closed` trips once failures
    /// reach `failure_threshold`.
    ///
    /// ```
    /// use throttle_machines::circuit_breaker::{CircuitBreaker, CircuitState};
    /// let r = CircuitBreaker::record(CircuitState::Closed, 2, 5.0, false, 3);
    /// assert_eq!(r.new_state, CircuitState::Open);
    /// assert_eq!(r.opened_at, 5.0);
    /// ```
    #[inline]
    #[must_use]
    pub const fn record(
        state: CircuitState,
        failures: u32,
        now: f64,
        success: bool,
        failure_threshold: u32,
    ) -> RecordResult {
        if success {
            return RecordResult {
                new_state: CircuitState::Closed,
                new_failures: 0,
                opened_at: 0.0,
            };
        }

        match state {
            CircuitState::HalfOpen | CircuitState::Open => RecordResult {
                new_state: CircuitState::Open,
                new_failures: failures,
                opened_at: now,
            },
            CircuitState::Closed => {
                let new_failures = failures.saturating_add(1);
                if new_failures >= failure_threshold {
                    RecordResult {
                        new_state: CircuitState::Open,
                        new_failures,
                        opened_at: now,
                    }
                } else {
                    RecordResult {
                        new_state: CircuitState::Closed,
                        new_failures,
                        opened_at: 0.0,
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests;
