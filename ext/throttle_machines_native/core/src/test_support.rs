//! Decision builders shared by the gate test modules.

use crate::gate::Decision;

/// An admitting decision, which never asks the caller to wait.
pub const fn allowed<S>(state: S) -> Decision<S> {
    Decision {
        allowed: true,
        state,
        retry_after: 0.0,
    }
}

/// A refusing decision that asks the caller to wait `retry_after` seconds.
pub const fn denied<S>(state: S, retry_after: f64) -> Decision<S> {
    Decision {
        allowed: false,
        state,
        retry_after,
    }
}
