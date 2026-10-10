//! Token bucket: burst capacity over a steady refill rate; each request
//! consumes one token.

use crate::gate::{Decision, Gate};

/// Token bucket state.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TokenBucketState {
    /// Current tokens in the bucket.
    pub tokens: f64,
    /// Timestamp of the last refill, in seconds.
    pub last_refill: f64,
}

/// Token bucket configuration.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TokenBucketParams {
    /// Maximum tokens (burst capacity).
    pub capacity: f64,
    /// Tokens added per second.
    pub refill_rate: f64,
}

/// Token bucket gate.
pub struct TokenBucket;

impl Gate for TokenBucket {
    type State = TokenBucketState;
    type Params = TokenBucketParams;

    /// ```
    /// use throttle_machines::gate::Gate;
    /// use throttle_machines::token_bucket::{TokenBucket, TokenBucketParams, TokenBucketState};
    /// let state = TokenBucketState { tokens: 10.0, last_refill: 0.0 };
    /// let params = TokenBucketParams { capacity: 10.0, refill_rate: 1.0 };
    /// let result = TokenBucket::check(state, 1.0, params);
    /// assert!(result.allowed);
    /// assert!((result.state.tokens - 9.0).abs() < 0.0001);
    /// ```
    #[inline]
    fn check(
        state: TokenBucketState,
        now: f64,
        params: TokenBucketParams,
    ) -> Decision<TokenBucketState> {
        let elapsed = now - state.last_refill;
        // `allow`, not `expect`: clippy only suggests `mul_add` when std is linked.
        #[allow(
            clippy::suboptimal_flops,
            reason = "`mul_add` is std-only (breaks no_std), and fusing would change the \
                      rounding that the Ruby and Redis backends' \
                      `tokens + elapsed * refill_rate` produce"
        )]
        let refilled = (state.tokens + elapsed * params.refill_rate).min(params.capacity);

        if refilled >= 1.0 {
            Decision {
                allowed: true,
                state: TokenBucketState {
                    tokens: refilled - 1.0,
                    last_refill: now,
                },
                retry_after: 0.0,
            }
        } else {
            Decision {
                allowed: false,
                state: TokenBucketState {
                    tokens: refilled,
                    last_refill: now,
                },
                retry_after: (1.0 - refilled) / params.refill_rate,
            }
        }
    }

    /// Pure, so identical to [`TokenBucket::check`]: `state.tokens` reflects a
    /// hypothetical consume.
    #[inline]
    fn peek(
        state: TokenBucketState,
        now: f64,
        params: TokenBucketParams,
    ) -> Decision<TokenBucketState> {
        Self::check(state, now, params)
    }
}

#[cfg(test)]
mod tests;
