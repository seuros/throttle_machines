//! Token Bucket rate limiting algorithm.
//!
//! The token bucket algorithm allows for burst capacity while maintaining
//! a steady average rate. Tokens are added at a constant refill rate up to
//! a maximum capacity, and each request consumes one token.

/// Result of a token bucket rate limit check.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TokenBucketResult {
    /// Whether the request is allowed.
    pub allowed: bool,
    /// Current number of tokens remaining after this check.
    pub new_tokens: f64,
    /// Seconds until the next request would be allowed (0 if allowed).
    pub retry_after: f64,
}

/// Check if a request is allowed under the token bucket algorithm.
///
/// # Arguments
///
/// * `tokens` - Current number of tokens in the bucket
/// * `last_refill` - Timestamp of the last refill in seconds
/// * `now` - Current timestamp in seconds
/// * `capacity` - Maximum number of tokens (burst capacity)
/// * `refill_rate` - Tokens added per second
///
/// # Returns
///
/// A `TokenBucketResult` indicating whether the request is allowed,
/// the new token count, and retry time if rate limited.
///
/// # Example
///
/// ```
/// use throttle_machines::token_bucket;
///
/// // Bucket with capacity 10, refilling at 1 token/second
/// let result = token_bucket::check(10.0, 0.0, 1.0, 10.0, 1.0);
/// assert!(result.allowed);
/// assert!((result.new_tokens - 9.0).abs() < 0.0001);
/// ```
#[inline]
pub fn check(
    tokens: f64,
    last_refill: f64,
    now: f64,
    capacity: f64,
    refill_rate: f64,
) -> TokenBucketResult {
    // Calculate tokens to add since last refill
    let elapsed = now - last_refill;
    let tokens_to_add = elapsed * refill_rate;

    // Refill up to capacity
    let refilled = if tokens + tokens_to_add > capacity {
        capacity
    } else {
        tokens + tokens_to_add
    };

    // Check if we have at least one token
    if refilled >= 1.0 {
        TokenBucketResult {
            allowed: true,
            new_tokens: refilled - 1.0,
            retry_after: 0.0,
        }
    } else {
        // Calculate time until we have 1 token
        let tokens_needed = 1.0 - refilled;
        let retry_after = tokens_needed / refill_rate;

        TokenBucketResult {
            allowed: false,
            new_tokens: refilled,
            retry_after,
        }
    }
}

/// Peek at the current state without consuming a token.
///
/// This is useful for checking remaining capacity without modifying state.
#[inline]
pub fn peek(
    tokens: f64,
    last_refill: f64,
    now: f64,
    capacity: f64,
    refill_rate: f64,
) -> TokenBucketResult {
    let elapsed = now - last_refill;
    let tokens_to_add = elapsed * refill_rate;
    let current_tokens = if tokens + tokens_to_add > capacity {
        capacity
    } else {
        tokens + tokens_to_add
    };

    if current_tokens >= 1.0 {
        TokenBucketResult {
            allowed: true,
            new_tokens: current_tokens - 1.0, // What it would be after consuming
            retry_after: 0.0,
        }
    } else {
        let tokens_needed = 1.0 - current_tokens;
        TokenBucketResult {
            allowed: false,
            new_tokens: current_tokens,
            retry_after: tokens_needed / refill_rate,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_full_bucket_allows() {
        let result = check(10.0, 0.0, 1.0, 10.0, 1.0);
        assert!(result.allowed);
        // Started with 10, added 1 (1 second elapsed), capped at 10, consumed 1 = 9
        assert!((result.new_tokens - 9.0).abs() < 0.0001);
    }

    #[test]
    fn test_empty_bucket_denies() {
        let result = check(0.0, 0.0, 0.0, 10.0, 1.0);
        assert!(!result.allowed);
        assert!(result.retry_after > 0.0);
    }

    #[test]
    fn test_refill_over_time() {
        // Start with 0 tokens, wait 5 seconds with refill rate of 1/sec
        let result = check(0.0, 0.0, 5.0, 10.0, 1.0);
        assert!(result.allowed);
        // Should have 5 tokens, consume 1 = 4
        assert!((result.new_tokens - 4.0).abs() < 0.0001);
    }

    #[test]
    fn test_capacity_cap() {
        // Start with 10 tokens (at capacity), wait 100 seconds
        let result = check(10.0, 0.0, 100.0, 10.0, 1.0);
        assert!(result.allowed);
        // Should still be capped at 10, consume 1 = 9
        assert!((result.new_tokens - 9.0).abs() < 0.0001);
    }

    #[test]
    fn test_retry_after_calculation() {
        // 0.5 tokens, need 1.0, refill rate 2.0 tokens/sec
        // Need 0.5 more tokens, at 2/sec = 0.25 seconds
        let result = check(0.5, 1.0, 1.0, 10.0, 2.0);
        assert!(!result.allowed);
        assert!((result.retry_after - 0.25).abs() < 0.0001);
    }

    #[test]
    fn test_peek_does_not_consume() {
        let result = peek(5.0, 0.0, 1.0, 10.0, 1.0);
        assert!(result.allowed);
        // Peek shows what it would be after consuming
        assert!((result.new_tokens - 5.0).abs() < 0.0001);
    }
}
