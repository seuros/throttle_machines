//! Fixed window: count requests per window; reset when it expires. Simple, but
//! allows bursts at window boundaries.

use crate::gate::{Decision, Gate};

/// Fixed window state.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FixedWindowState {
    /// Request count in the current window.
    pub count: u64,
    /// Timestamp the current window started.
    pub window_start: f64,
}

/// Fixed window configuration.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FixedWindowParams {
    /// Window duration, in seconds.
    pub window_size: f64,
    /// Maximum requests per window.
    pub limit: u64,
}

/// Fixed window gate.
pub struct FixedWindow;

impl FixedWindow {
    /// Shared evaluation: `increment` is 1 for `check`, 0 for `peek`.
    #[inline]
    fn evaluate(
        state: FixedWindowState,
        now: f64,
        params: FixedWindowParams,
        increment: u64,
    ) -> Decision<FixedWindowState> {
        let window_end = state.window_start + params.window_size;

        if now >= window_end {
            Decision {
                allowed: true,
                state: FixedWindowState {
                    count: increment,
                    window_start: now,
                },
                retry_after: 0.0,
            }
        } else if state.count < params.limit {
            Decision {
                allowed: true,
                state: FixedWindowState {
                    count: state.count + increment,
                    window_start: state.window_start,
                },
                retry_after: 0.0,
            }
        } else {
            Decision {
                allowed: false,
                state,
                retry_after: window_end - now,
            }
        }
    }

    /// Remaining requests in the current window.
    #[inline]
    #[must_use]
    pub const fn remaining(count: u64, limit: u64) -> u64 {
        limit.saturating_sub(count)
    }
}

impl Gate for FixedWindow {
    type State = FixedWindowState;
    type Params = FixedWindowParams;

    /// ```
    /// use throttle_machines::gate::Gate;
    /// use throttle_machines::fixed_window::{FixedWindow, FixedWindowParams, FixedWindowState};
    /// let state = FixedWindowState { count: 0, window_start: 0.0 };
    /// let params = FixedWindowParams { window_size: 60.0, limit: 10 };
    /// let result = FixedWindow::check(state, 1.0, params);
    /// assert!(result.allowed);
    /// assert_eq!(result.state.count, 1);
    /// ```
    #[inline]
    fn check(
        state: FixedWindowState,
        now: f64,
        params: FixedWindowParams,
    ) -> Decision<FixedWindowState> {
        Self::evaluate(state, now, params, 1)
    }

    #[inline]
    fn peek(
        state: FixedWindowState,
        now: f64,
        params: FixedWindowParams,
    ) -> Decision<FixedWindowState> {
        Self::evaluate(state, now, params, 0)
    }
}

#[cfg(test)]
mod tests;
