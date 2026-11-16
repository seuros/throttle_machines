//! Generic Cell Rate Algorithm: smooth rate limiting through a theoretical
//! arrival time (TAT) that each admission pushes one emission interval on.
//!
//! Every count is exact. A policy exists only when its burst ceiling
//! (`delay_tolerance + emission_interval`) is a `Duration` and holds at most
//! `u64::MAX` emission intervals, so the capacity a gate answers is never
//! clamped. The TAT never saturates: an admission that would push it past
//! `Duration::MAX` is refused as [`Refusal::Overflow`] with nothing changed,
//! and `peek` counts only the admissions whose TAT fits. No later instant
//! lifts an `Overflow`, so `retry_after` answers `Duration::MAX` (never)
//! when the next admission's TAT cannot fit; the subtractions that measure
//! how far ahead the TAT runs floor at zero.

use core::num::NonZeroU64;
use core::time::Duration;

use crate::gate::{count, fits, share, times};
use crate::{Gate, Refusal};

/// How a [`Gcra`] admits: one call per `emission_interval`, with up to
/// `delay_tolerance` of calls ahead of schedule allowed as a burst.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GcraPolicy {
    emission_interval: Duration,
    delay_tolerance: Duration,
    /// `delay_tolerance + emission_interval`: how far ahead of `now` the TAT
    /// may run after an admission.
    ceiling: Duration,
}

impl GcraPolicy {
    /// `None` for a zero `emission_interval`, which would admit without
    /// bound, and for a burst the gate could not count exactly: a burst
    /// ceiling (`delay_tolerance + emission_interval`) past `Duration::MAX`,
    /// or one holding more than `u64::MAX` emission intervals.
    ///
    /// ```
    /// use core::time::Duration;
    /// use throttle_machines::GcraPolicy;
    ///
    /// assert!(GcraPolicy::new(Duration::from_millis(100), Duration::ZERO).is_some());
    /// assert!(GcraPolicy::new(Duration::ZERO, Duration::ZERO).is_none());
    /// assert!(GcraPolicy::new(Duration::MAX, Duration::from_nanos(1)).is_none());
    /// assert!(GcraPolicy::new(Duration::from_nanos(1), Duration::from_nanos(u64::MAX)).is_none());
    /// ```
    #[must_use]
    pub const fn new(emission_interval: Duration, delay_tolerance: Duration) -> Option<Self> {
        if emission_interval.is_zero() {
            return None;
        }
        let Some(ceiling) = delay_tolerance.checked_add(emission_interval) else {
            return None;
        };
        // The capacity, the most a gate answers, must be a `u64`.
        if ceiling.as_nanos() / emission_interval.as_nanos() > u64::MAX as u128 {
            return None;
        }
        Some(Self {
            emission_interval,
            delay_tolerance,
            ceiling,
        })
    }

    /// `limit` calls per `period`, `burst` of them back to back from idle
    /// (one means no burst). The interval is `period / limit` rounded up to
    /// the nanosecond, so the rate never exceeds the one asked for. `None`
    /// for a zero `period`, or a burst ceiling (`burst` intervals) past
    /// `Duration::MAX`.
    ///
    /// ```
    /// use core::num::NonZeroU64;
    /// use core::time::Duration;
    /// use throttle_machines::GcraPolicy;
    ///
    /// let ten = NonZeroU64::new(10).unwrap();
    /// let policy = GcraPolicy::per(Duration::from_secs(1), ten, NonZeroU64::new(3).unwrap()).unwrap();
    /// assert_eq!(policy.emission_interval(), Duration::from_millis(100));
    /// assert_eq!(policy.delay_tolerance(), Duration::from_millis(200));
    /// ```
    #[must_use]
    pub fn per(period: Duration, limit: NonZeroU64, burst: NonZeroU64) -> Option<Self> {
        let emission_interval = share(period, limit)?;
        let delay_tolerance = times(emission_interval, u128::from(burst.get() - 1))?;
        Self::new(emission_interval, delay_tolerance)
    }

    /// The span one admission pushes the TAT on.
    #[must_use]
    pub const fn emission_interval(&self) -> Duration {
        self.emission_interval
    }

    /// How far ahead of `now` the TAT may be while calls are still admitted.
    #[must_use]
    pub const fn delay_tolerance(&self) -> Duration {
        self.delay_tolerance
    }

    /// Calls the tolerance admits for a TAT running `ahead` of `now`: how
    /// far below the burst ceiling it sits, in emission intervals. At most
    /// the capacity, which `new` proved fits a `u64`.
    fn room(&self, ahead: Duration) -> u128 {
        fits(self.ceiling.saturating_sub(ahead), self.emission_interval)
    }
}

/// A GCRA limiter: a [`GcraPolicy`] and the TAT it has reached.
///
/// ```
/// use core::time::Duration;
/// use throttle_machines::{Gate, Gcra, GcraPolicy, Refusal};
///
/// let policy = GcraPolicy::new(Duration::from_secs(1), Duration::ZERO).unwrap();
/// let mut gcra = Gcra::new(policy);
/// let now = Duration::from_secs(10);
/// assert_eq!(gcra.check(now), Ok(0));
/// assert_eq!(gcra.check(now), Err(Refusal::Throttled));
/// assert_eq!(gcra.retry_after(now), Duration::from_secs(1));
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Gcra {
    policy: GcraPolicy,
    tat: Duration,
}

impl Gcra {
    /// A limiter that has admitted nothing: its TAT is the epoch.
    #[must_use]
    pub const fn new(policy: GcraPolicy) -> Self {
        Self {
            policy,
            tat: Duration::ZERO,
        }
    }

    /// A limiter resumed at a TAT read from [`tat`](Self::tat), for a caller
    /// that keeps the state elsewhere between calls. Every TAT is valid: one
    /// at or before `now` means fully recovered.
    #[must_use]
    pub const fn restored(policy: GcraPolicy, tat: Duration) -> Self {
        Self { policy, tat }
    }

    /// The policy this limiter admits by.
    #[must_use]
    pub const fn policy(&self) -> GcraPolicy {
        self.policy
    }

    /// The theoretical arrival time of the next call on schedule.
    #[must_use]
    pub const fn tat(&self) -> Duration {
        self.tat
    }

    /// What `check` answers at `now`: the calls admitted, at least one, and
    /// the TAT one admission leaves.
    fn decide(&self, now: Duration) -> Result<(u64, Duration), Refusal> {
        let interval = self.policy.emission_interval;
        let ahead = self.tat.saturating_sub(now);
        if ahead > self.policy.delay_tolerance {
            return Err(Refusal::Throttled);
        }
        let next = self
            .tat
            .max(now)
            .checked_add(interval)
            .ok_or(Refusal::Overflow)?;
        // Admissions whose TAT still fits: `next`, then one interval on for
        // each whole interval left before `Duration::MAX`.
        let fit = fits(Duration::MAX.saturating_sub(next), interval).saturating_add(1);
        // Within tolerance, the room is at least one interval and at most
        // the capacity, a `u64`.
        Ok((count(self.policy.room(ahead).min(fit)), next))
    }
}

impl Gate for Gcra {
    fn check(&mut self, now: Duration) -> Result<u64, Refusal> {
        let (admits, next) = self.decide(now)?;
        self.tat = next;
        // `decide` answers at least one, and this admission spends exactly
        // one: the TAT and the room both move one interval.
        Ok(admits - 1)
    }

    fn peek(&self, now: Duration) -> Result<u64, Refusal> {
        self.decide(now).map(|(admits, _)| admits)
    }

    /// `Duration::MAX` when the next admission's TAT cannot fit a
    /// `Duration`, at any later instant.
    fn retry_after(&self, now: Duration) -> Duration {
        let wait = self
            .tat
            .saturating_sub(now)
            .saturating_sub(self.policy.delay_tolerance);
        // `now + wait` is at most the TAT, so it fits.
        let at = now.saturating_add(wait);
        if self
            .tat
            .max(at)
            .checked_add(self.policy.emission_interval)
            .is_none()
        {
            return Duration::MAX;
        }
        wait
    }

    /// Pulls the TAT back one emission interval, never before the epoch.
    fn refund(&mut self) {
        self.tat = self.tat.saturating_sub(self.policy.emission_interval);
    }
}

#[cfg(test)]
mod tests;
