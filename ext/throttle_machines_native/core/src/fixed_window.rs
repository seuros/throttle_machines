//! Fixed Window rate limiting algorithm.
//!
//! The fixed window algorithm counts requests within a time window.
//! When the window expires, the counter resets. Simple but can allow
//! bursts at window boundaries.

/// Result of a fixed window rate limit check.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FixedWindowResult {
    /// Whether the request is allowed.
    pub allowed: bool,
    /// Current count after this check.
    pub new_count: u64,
    /// Seconds until the window resets (0 if allowed and not at limit).
    pub retry_after: f64,
}

/// Check if a request is allowed under the fixed window algorithm.
///
/// # Arguments
///
/// * `count` - Current request count in the window
/// * `window_start` - Timestamp when the current window started
/// * `now` - Current timestamp in seconds
/// * `window_size` - Duration of the window in seconds
/// * `limit` - Maximum requests allowed per window
///
/// # Returns
///
/// A `FixedWindowResult` indicating whether the request is allowed,
/// the new count, and time until window reset if rate limited.
///
/// # Example
///
/// ```
/// use throttle_machines::fixed_window;
///
/// // 10 requests per 60 second window
/// let result = fixed_window::check(0, 0.0, 1.0, 60.0, 10);
/// assert!(result.allowed);
/// assert_eq!(result.new_count, 1);
/// ```
#[inline]
pub fn check(
    count: u64,
    window_start: f64,
    now: f64,
    window_size: f64,
    limit: u64,
) -> FixedWindowResult {
    // Check if window has expired
    let window_end = window_start + window_size;

    if now >= window_end {
        // Window expired, start new window
        FixedWindowResult {
            allowed: true,
            new_count: 1,
            retry_after: 0.0,
        }
    } else if count < limit {
        // Within limit
        FixedWindowResult {
            allowed: true,
            new_count: count + 1,
            retry_after: 0.0,
        }
    } else {
        // Rate limited
        FixedWindowResult {
            allowed: false,
            new_count: count,
            retry_after: window_end - now,
        }
    }
}

/// Peek at the current state without incrementing the counter.
#[inline]
pub fn peek(
    count: u64,
    window_start: f64,
    now: f64,
    window_size: f64,
    limit: u64,
) -> FixedWindowResult {
    let window_end = window_start + window_size;

    if now >= window_end {
        // Window would expire
        FixedWindowResult {
            allowed: true,
            new_count: 0,
            retry_after: 0.0,
        }
    } else if count < limit {
        FixedWindowResult {
            allowed: true,
            new_count: count,
            retry_after: 0.0,
        }
    } else {
        FixedWindowResult {
            allowed: false,
            new_count: count,
            retry_after: window_end - now,
        }
    }
}

/// Calculate remaining requests in the current window.
#[inline]
pub fn remaining(count: u64, limit: u64) -> u64 {
    if count >= limit {
        0
    } else {
        limit - count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_first_request_allowed() {
        let result = check(0, 0.0, 1.0, 60.0, 10);
        assert!(result.allowed);
        assert_eq!(result.new_count, 1);
        assert_eq!(result.retry_after, 0.0);
    }

    #[test]
    fn test_at_limit_denied() {
        let result = check(10, 0.0, 30.0, 60.0, 10);
        assert!(!result.allowed);
        assert_eq!(result.new_count, 10);
        assert!((result.retry_after - 30.0).abs() < 0.0001);
    }

    #[test]
    fn test_window_reset() {
        // Window started at 0, size 60, now at 61 (past window)
        let result = check(10, 0.0, 61.0, 60.0, 10);
        assert!(result.allowed);
        assert_eq!(result.new_count, 1);
    }

    #[test]
    fn test_remaining() {
        assert_eq!(remaining(0, 10), 10);
        assert_eq!(remaining(5, 10), 5);
        assert_eq!(remaining(10, 10), 0);
        assert_eq!(remaining(15, 10), 0); // Over limit
    }

    #[test]
    fn test_peek_does_not_increment() {
        let result = peek(5, 0.0, 30.0, 60.0, 10);
        assert!(result.allowed);
        assert_eq!(result.new_count, 5); // Not incremented
    }
}
