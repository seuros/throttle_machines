//! Fixed window: up to `limit` calls per window, the count starting again
//! when the window ends. Simple, but admits up to twice the limit across a
//! window boundary.
//!
//! A window whose end would pass `Duration::MAX` never ends: no instant a
//! `Duration` holds opens the next one, and `retry_after` answers
//! `Duration::MAX` (never) while it is spent.

use core::num::NonZeroU64;
use core::time::Duration;

use crate::{Gate, Refusal};

/// How a [`FixedWindow`] admits: `limit` calls per `window`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FixedWindowPolicy {
    window: Duration,
    limit: NonZeroU64,
}

impl FixedWindowPolicy {
    /// `None` for a zero `window`, which would never hold a call.
    #[must_use]
    pub const fn new(window: Duration, limit: NonZeroU64) -> Option<Self> {
        if window.is_zero() {
            return None;
        }
        Some(Self { window, limit })
    }

    /// The length of a window.
    #[must_use]
    pub const fn window(&self) -> Duration {
        self.window
    }

    /// The most calls one window admits.
    #[must_use]
    pub const fn limit(&self) -> NonZeroU64 {
        self.limit
    }
}

/// A fixed window counter: a [`FixedWindowPolicy`], the calls admitted in
/// the current window, and when it opened.
///
/// A window opens at the first call after the previous one ended; the first
/// window opens at the epoch.
///
/// ```
/// use core::num::NonZeroU64;
/// use core::time::Duration;
/// use throttle_machines::{FixedWindow, FixedWindowPolicy, Gate, Refusal};
///
/// let policy = FixedWindowPolicy::new(Duration::from_secs(60), NonZeroU64::new(1).unwrap()).unwrap();
/// let mut window = FixedWindow::new(policy);
/// assert_eq!(window.check(Duration::from_secs(1)), Ok(0));
/// assert_eq!(window.check(Duration::from_secs(2)), Err(Refusal::Throttled));
/// assert_eq!(window.retry_after(Duration::from_secs(2)), Duration::from_secs(58));
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FixedWindow {
    policy: FixedWindowPolicy,
    count: u64,
    window_start: Duration,
}

impl FixedWindow {
    /// A counter that has admitted nothing, in a window opened at the epoch.
    #[must_use]
    pub const fn new(policy: FixedWindowPolicy) -> Self {
        Self {
            policy,
            count: 0,
            window_start: Duration::ZERO,
        }
    }

    /// A counter resumed from [`count`](Self::count) and
    /// [`window_start`](Self::window_start); `None` when `count` is above
    /// the limit.
    #[must_use]
    pub const fn restored(
        policy: FixedWindowPolicy,
        count: u64,
        window_start: Duration,
    ) -> Option<Self> {
        if count > policy.limit.get() {
            return None;
        }
        Some(Self {
            policy,
            count,
            window_start,
        })
    }

    /// The policy this counter admits by.
    #[must_use]
    pub const fn policy(&self) -> FixedWindowPolicy {
        self.policy
    }

    /// Calls admitted in the window opened at
    /// [`window_start`](Self::window_start).
    #[must_use]
    pub const fn count(&self) -> u64 {
        self.count
    }

    /// When the current window opened.
    #[must_use]
    pub const fn window_start(&self) -> Duration {
        self.window_start
    }

    /// When the current window ends; `None` when it never does.
    const fn window_end(&self) -> Option<Duration> {
        self.window_start.checked_add(self.policy.window)
    }

    /// The count and window start as of `now`: a fresh window opened at
    /// `now` once the current one has ended.
    fn current(&self, now: Duration) -> (u64, Duration) {
        if self.window_end().is_some_and(|end| now >= end) {
            (0, now)
        } else {
            (self.count, self.window_start)
        }
    }

    const fn left(&self, admitted: u64) -> Result<u64, Refusal> {
        match self.policy.limit.get().checked_sub(admitted) {
            Some(0) | None => Err(Refusal::Throttled),
            Some(left) => Ok(left),
        }
    }
}

impl Gate for FixedWindow {
    fn check(&mut self, now: Duration) -> Result<u64, Refusal> {
        let (count, window_start) = self.current(now);
        // `left` answers at least one, so count < limit: neither step wraps.
        let left = self.left(count)?;
        self.count = count + 1;
        self.window_start = window_start;
        Ok(left - 1)
    }

    fn peek(&self, now: Duration) -> Result<u64, Refusal> {
        self.left(self.current(now).0)
    }

    fn retry_after(&self, now: Duration) -> Duration {
        let (count, window_start) = self.current(now);
        if self.left(count).is_ok() {
            return Duration::ZERO;
        }
        // Spent, so the window is still open at `now`: `now` is before its end.
        window_start
            .checked_add(self.policy.window)
            .map_or(Duration::MAX, |end| end.saturating_sub(now))
    }

    /// Takes one call off the current window's count.
    fn refund(&mut self) {
        self.count = self.count.saturating_sub(1);
    }
}

#[cfg(test)]
mod tests;
