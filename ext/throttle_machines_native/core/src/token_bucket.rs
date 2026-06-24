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
mod tests {
    use super::*;

    const CAP10_RATE1: TokenBucketParams = TokenBucketParams {
        capacity: 10.0,
        refill_rate: 1.0,
    };

    #[test]
    fn test_full_bucket_allows() {
        let state = TokenBucketState {
            tokens: 10.0,
            last_refill: 0.0,
        };
        let result = TokenBucket::check(state, 1.0, CAP10_RATE1);
        assert!(result.allowed);
        assert!((result.state.tokens - 9.0).abs() < 0.0001);
    }

    #[test]
    fn test_empty_bucket_denies() {
        let state = TokenBucketState {
            tokens: 0.0,
            last_refill: 0.0,
        };
        let result = TokenBucket::check(state, 0.0, CAP10_RATE1);
        assert!(!result.allowed);
        assert!(result.retry_after > 0.0);
    }

    #[test]
    fn test_refill_over_time() {
        let state = TokenBucketState {
            tokens: 0.0,
            last_refill: 0.0,
        };
        let result = TokenBucket::check(state, 5.0, CAP10_RATE1);
        assert!(result.allowed);
        assert!((result.state.tokens - 4.0).abs() < 0.0001);
    }

    #[test]
    fn test_capacity_cap() {
        let state = TokenBucketState {
            tokens: 10.0,
            last_refill: 0.0,
        };
        let result = TokenBucket::check(state, 100.0, CAP10_RATE1);
        assert!(result.allowed);
        assert!((result.state.tokens - 9.0).abs() < 0.0001);
    }

    #[test]
    fn test_retry_after_calculation() {
        // 0.5 tokens, need 0.5 more at 2/sec -> 0.25s.
        let state = TokenBucketState {
            tokens: 0.5,
            last_refill: 1.0,
        };
        let params = TokenBucketParams {
            capacity: 10.0,
            refill_rate: 2.0,
        };
        let result = TokenBucket::check(state, 1.0, params);
        assert!(!result.allowed);
        assert!((result.retry_after - 0.25).abs() < 0.0001);
    }

    #[test]
    fn test_peek_does_not_consume() {
        let state = TokenBucketState {
            tokens: 5.0,
            last_refill: 0.0,
        };
        let result = TokenBucket::peek(state, 1.0, CAP10_RATE1);
        assert!(result.allowed);
        assert!((result.state.tokens - 5.0).abs() < 0.0001);
    }
}
