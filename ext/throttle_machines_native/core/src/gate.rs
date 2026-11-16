//! The contract every rate limiter honours.

use core::num::NonZeroU64;
use core::time::Duration;

use crate::Refusal;

/// An admission gate over a caller-supplied monotonic clock: `now` is a
/// [`Duration`] since an epoch the caller picks, the same for every call on
/// one gate.
///
/// A gate reads no clock and keeps no history beyond its own state. Calls at
/// an earlier `now` than an earlier call are answered, never refused for it:
/// each algorithm is at least as strict at an earlier instant as at a later
/// one, so a regressed clock can delay admissions but never grant extra ones.
pub trait Gate {
    /// Admit one call at `now`. Honoured: how many more calls the gate would
    /// admit at the same instant, exactly. A refusal changes nothing.
    ///
    /// # Errors
    ///
    /// [`Refusal::Throttled`] when the limit is spent at `now`;
    /// [`Refusal::Overflow`] (GCRA only) when admitting would push the TAT
    /// past `Duration::MAX`.
    fn check(&mut self, now: Duration) -> Result<u64, Refusal>;

    /// How many calls [`check`](Self::check) would admit back to back at
    /// `now`, exactly, at least one, without consuming any.
    ///
    /// # Errors
    ///
    /// The refusal `check` would answer at `now`.
    fn peek(&self, now: Duration) -> Result<u64, Refusal>;

    /// How long after `now` the next call is admitted; zero when one is
    /// admitted at `now`, and `Duration::MAX` when none is at any instant a
    /// `Duration` can hold.
    fn retry_after(&self, now: Duration) -> Duration;

    /// Give back one admission `check` granted, for a call admitted only when
    /// every gate it spends admits it. Refunding an admission never granted
    /// grants capacity never earned, up to a fresh gate's.
    fn refund(&mut self);
}

/// `span * count`, or `None` past `Duration::MAX`.
pub fn times(span: Duration, count: u128) -> Option<Duration> {
    nanos(span.as_nanos().checked_mul(count)?)
}

/// How many whole `span`s fit in `total`. `span` is never zero: the policies
/// that hold one refuse it.
pub fn fits(total: Duration, span: Duration) -> u128 {
    total.as_nanos().checked_div(span.as_nanos()).unwrap_or(0)
}

/// `total / count`, rounded up, so a rate built from it never exceeds the
/// `count` per `total` asked for. `None` for a zero `total`.
pub fn share(total: Duration, count: NonZeroU64) -> Option<Duration> {
    let share = total.as_nanos().div_ceil(u128::from(count.get()));
    if share == 0 {
        return None;
    }
    nanos(share)
}

/// A count already bounded by a `u64` (a policy's capacity, the tokens
/// held), as the `u64` a gate answers.
pub fn count(value: u128) -> u64 {
    u64::try_from(value).unwrap_or_else(|_| {
        debug_assert!(false, "a count past the u64 bound its policy proved");
        u64::MAX
    })
}

fn nanos(value: u128) -> Option<Duration> {
    const PER_SECOND: u128 = 1_000_000_000;
    let seconds = u64::try_from(value / PER_SECOND).ok()?;
    // The remainder is below a billion, so it fits.
    let rest = u32::try_from(value % PER_SECOND).ok()?;
    Some(Duration::new(seconds, rest))
}
