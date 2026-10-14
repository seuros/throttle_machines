//! The shared admission-gate contract: pure `check`/`peek` over caller-held
//! state, returning a [`Decision`]. All rate limiters and the circuit breaker
//! implement [`Gate`].

/// Rounding slack, in units of the clock's own precision.
const SLACK_ULPS: f64 = 64.0;

/// Absolute rounding slack for a time comparison at clock reading `t`.
///
/// Times are running sums and differences of `f64` seconds, so an on-schedule
/// arrival can miss an exact boundary by a few ulps. The slack scales with the
/// clock's magnitude, so epoch-second clocks are covered as well as monotonic
/// ones (at ~1.7e9 s it is ~24 µs, far below any practical interval at that
/// precision).
#[inline]
pub(crate) fn rounding_slack(t: f64) -> f64 {
    f64::EPSILON * SLACK_ULPS * t.abs().max(1.0)
}

/// The outcome of an admission decision. `S` is the algorithm's state type;
/// `state` is the state after the operation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Decision<S> {
    /// Whether the call is allowed to proceed.
    pub allowed: bool,
    /// The state after this decision.
    pub state: S,
    /// Seconds until the next allowed call (0 if allowed).
    pub retry_after: f64,
}

/// An admission gate: a pure decision over caller-held state. Implementors are
/// zero-sized; the caller stores `State` and passes it in each call.
///
/// ```
/// use throttle_machines::gate::{Decision, Gate};
/// use throttle_machines::gcra::{Gcra, GcraParams};
///
/// fn admit<G: Gate>(state: G::State, now: f64, params: G::Params) -> Decision<G::State> {
///     G::check(state, now, params)
/// }
///
/// let params = GcraParams { emission_interval: 0.1, delay_tolerance: 0.0 };
/// assert!(admit::<Gcra>(0.0, 1.0, params).allowed);
/// ```
pub trait Gate {
    /// The caller-held state this gate operates over.
    type State: Copy;
    /// The configuration that parameterizes the decision.
    type Params: Copy;

    /// The consuming admission decision.
    fn check(state: Self::State, now: f64, params: Self::Params) -> Decision<Self::State>;

    /// Observe the decision without consuming.
    fn peek(state: Self::State, now: f64, params: Self::Params) -> Decision<Self::State>;
}
