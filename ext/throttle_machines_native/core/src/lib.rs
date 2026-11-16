//! Rate limiting on a caller-supplied clock: GCRA, token bucket and fixed
//! window, each a small `Copy` value behind the shared [`Gate`] contract.
//!
//! The crate is `no_std` and allocation-free; it reads no clock. `now` is a
//! [`Duration`](core::time::Duration) since an epoch the caller picks, and so
//! is every span. A refused call answers [`Refusal`] and changes nothing.
//!
//! The `std` feature adds [`KeyedGcra`], which keeps per-key GCRA state in a
//! sharded, mutex-guarded map.
//!
//! ```
//! use core::num::NonZeroU64;
//! use core::time::Duration;
//! use throttle_machines::{Gate, Gcra, GcraPolicy, Refusal};
//!
//! let policy = GcraPolicy::per(Duration::from_secs(1), NonZeroU64::new(2).unwrap(), NonZeroU64::MIN)
//!     .unwrap();
//! let mut gcra = Gcra::new(policy);
//! let now = Duration::from_secs(100);
//! assert_eq!(gcra.check(now), Ok(0));
//! assert_eq!(gcra.check(now), Err(Refusal::Throttled));
//! assert_eq!(gcra.retry_after(now), Duration::from_millis(500));
//! ```

#![no_std]
#![cfg_attr(not(test), deny(clippy::indexing_slicing))]

#[cfg(feature = "std")]
extern crate std;

mod fixed_window;
mod gate;
mod gcra;
#[cfg(feature = "std")]
mod keyed;
mod refusal;
mod token_bucket;

/// Compiles and runs the README's examples as doctests.
#[cfg(doctest)]
#[doc = include_str!("../README.md")]
struct ReadmeDoctests;

pub use fixed_window::{FixedWindow, FixedWindowPolicy};
pub use gate::Gate;
pub use gcra::{Gcra, GcraPolicy};
#[cfg(feature = "std")]
pub use keyed::KeyedGcra;
pub use refusal::Refusal;
pub use token_bucket::{TokenBucket, TokenBucketPolicy};
