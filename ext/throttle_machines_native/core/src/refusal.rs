use core::fmt;

/// Why a call was not honoured. A refused call changed nothing: not a TAT,
/// not a token, not a count, not a tracked key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    /// The limit is spent at the instant supplied; `retry_after` says how
    /// long until the next admission. It is an answer about that instant, not
    /// a recorded fact: the same call at another instant may be honoured.
    Throttled,
    /// Only [`KeyedGcra`](crate::KeyedGcra) answers it: the key is not
    /// tracked, its shard holds as many keys as it may, and none of them has
    /// recovered yet.
    Full,
    /// Only GCRA answers it: admitting the call would push the TAT past
    /// `Duration::MAX`. No later instant lifts it: the TAT only advances.
    Overflow,
}

impl fmt::Display for Refusal {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Throttled => "the limit is spent at this instant",
            Self::Full => "the shard tracks as many keys as it may",
            Self::Overflow => "the TAT would pass Duration::MAX",
        })
    }
}

impl core::error::Error for Refusal {}
