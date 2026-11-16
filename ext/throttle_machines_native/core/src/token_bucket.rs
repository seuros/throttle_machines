//! Token bucket: up to `capacity` calls back to back, refilled one token
//! every `refill_every`.
//!
//! A token due past `Duration::MAX` is never earned: `retry_after` answers
//! `Duration::MAX` (never) for an empty bucket whose next token falls there.

use core::num::NonZeroU64;
use core::time::Duration;

use crate::gate::{count, fits, share, times};
use crate::{Gate, Refusal};

/// How a [`TokenBucket`] admits: a burst of `capacity`, one more call per
/// `refill_every`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TokenBucketPolicy {
    capacity: NonZeroU64,
    refill_every: Duration,
}

impl TokenBucketPolicy {
    /// `None` for a zero `refill_every`, which would refill without bound.
    #[must_use]
    pub const fn new(capacity: NonZeroU64, refill_every: Duration) -> Option<Self> {
        if refill_every.is_zero() {
            return None;
        }
        Some(Self {
            capacity,
            refill_every,
        })
    }

    /// `limit` calls per `period`, all of them available as a burst. The
    /// refill span is `period / limit` rounded up to the nanosecond; `None`
    /// for a zero `period`.
    ///
    /// ```
    /// use core::num::NonZeroU64;
    /// use core::time::Duration;
    /// use throttle_machines::TokenBucketPolicy;
    ///
    /// let policy = TokenBucketPolicy::per(Duration::from_secs(60), NonZeroU64::new(3).unwrap()).unwrap();
    /// assert_eq!(policy.capacity().get(), 3);
    /// assert_eq!(policy.refill_every(), Duration::from_secs(20));
    /// ```
    #[must_use]
    pub fn per(period: Duration, limit: NonZeroU64) -> Option<Self> {
        Self::new(limit, share(period, limit)?)
    }

    /// The most tokens the bucket holds.
    #[must_use]
    pub const fn capacity(&self) -> NonZeroU64 {
        self.capacity
    }

    /// The span that earns one token.
    #[must_use]
    pub const fn refill_every(&self) -> Duration {
        self.refill_every
    }
}

/// A token bucket: a [`TokenBucketPolicy`], the tokens held, and the instant
/// refill credit was counted up to.
///
/// ```
/// use core::num::NonZeroU64;
/// use core::time::Duration;
/// use throttle_machines::{Gate, Refusal, TokenBucket, TokenBucketPolicy};
///
/// let policy = TokenBucketPolicy::new(NonZeroU64::new(2).unwrap(), Duration::from_secs(1)).unwrap();
/// let mut bucket = TokenBucket::new(policy);
/// let now = Duration::from_secs(5);
/// assert_eq!(bucket.check(now), Ok(1));
/// assert_eq!(bucket.check(now), Ok(0));
/// assert_eq!(bucket.check(now), Err(Refusal::Throttled));
/// assert_eq!(bucket.check(now + Duration::from_secs(1)), Ok(0));
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TokenBucket {
    policy: TokenBucketPolicy,
    tokens: u64,
    refilled_at: Duration,
}

impl TokenBucket {
    /// A full bucket.
    #[must_use]
    pub const fn new(policy: TokenBucketPolicy) -> Self {
        Self {
            policy,
            tokens: policy.capacity.get(),
            refilled_at: Duration::ZERO,
        }
    }

    /// A bucket resumed from [`tokens`](Self::tokens) and
    /// [`refilled_at`](Self::refilled_at); `None` when `tokens` is above the
    /// capacity.
    #[must_use]
    pub const fn restored(
        policy: TokenBucketPolicy,
        tokens: u64,
        refilled_at: Duration,
    ) -> Option<Self> {
        if tokens > policy.capacity.get() {
            return None;
        }
        Some(Self {
            policy,
            tokens,
            refilled_at,
        })
    }

    /// The policy this bucket admits by.
    #[must_use]
    pub const fn policy(&self) -> TokenBucketPolicy {
        self.policy
    }

    /// Tokens held as of [`refilled_at`](Self::refilled_at).
    #[must_use]
    pub const fn tokens(&self) -> u64 {
        self.tokens
    }

    /// The instant refill credit is counted from. A full bucket earns
    /// nothing, so its count starts again when a token is spent.
    #[must_use]
    pub const fn refilled_at(&self) -> Duration {
        self.refilled_at
    }

    /// Tokens and the refill instant as of `now`. A partial span earned
    /// toward the next token is kept; nothing is banked past capacity.
    fn refilled(&self, now: Duration) -> (u64, Duration) {
        let capacity = self.policy.capacity.get();
        let earned = fits(
            now.saturating_sub(self.refilled_at),
            self.policy.refill_every,
        );
        let tokens = u128::from(self.tokens).saturating_add(earned);
        if tokens >= u128::from(capacity) {
            return (capacity, self.refilled_at.max(now));
        }
        // Below capacity, so `earned` spans fit inside `now - refilled_at`.
        let spent = times(self.policy.refill_every, earned).unwrap_or(Duration::ZERO);
        (count(tokens), self.refilled_at.saturating_add(spent))
    }
}

impl Gate for TokenBucket {
    fn check(&mut self, now: Duration) -> Result<u64, Refusal> {
        let (tokens, refilled_at) = self.refilled(now);
        let left = tokens.checked_sub(1).ok_or(Refusal::Throttled)?;
        self.tokens = left;
        self.refilled_at = refilled_at;
        Ok(left)
    }

    fn peek(&self, now: Duration) -> Result<u64, Refusal> {
        match self.refilled(now) {
            (0, _) => Err(Refusal::Throttled),
            (tokens, _) => Ok(tokens),
        }
    }

    fn retry_after(&self, now: Duration) -> Duration {
        match self.refilled(now) {
            // Empty, so the next token is due after `now`.
            (0, refilled_at) => refilled_at
                .checked_add(self.policy.refill_every)
                .map_or(Duration::MAX, |due| due.saturating_sub(now)),
            _ => Duration::ZERO,
        }
    }

    /// Puts one token back, never past capacity.
    fn refund(&mut self) {
        self.tokens = self
            .tokens
            .saturating_add(1)
            .min(self.policy.capacity.get());
    }
}

#[cfg(test)]
mod tests;
