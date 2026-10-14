//! Rate limiting algorithms for high-performance applications.
//!
//! This crate provides three rate limiting algorithms:
//! - GCRA (Generic Cell Rate Algorithm)
//! - Token Bucket
//! - Fixed Window
//!
//! plus a circuit breaker. All four implement the shared [`gate::Gate`]
//! contract: a pure, caller-holds-state decision returning a [`gate::Decision`].
//!
//! All algorithms are `no_std` compatible when the `std` feature is disabled.
//! With `std`, [`KeyedGcra`] keeps per-key GCRA state on a monotonic clock.

#![cfg_attr(not(feature = "std"), no_std)]

pub mod circuit_breaker;
pub mod fixed_window;
pub mod gate;
pub mod gcra;
#[cfg(feature = "std")]
pub mod keyed;
pub mod token_bucket;

#[cfg(test)]
mod test_support;

/// Compiles and runs the README's examples as doctests.
#[cfg(doctest)]
#[doc = include_str!("../README.md")]
struct ReadmeDoctests;

pub use circuit_breaker::{
    BreakerParams, BreakerState, CircuitBreaker, CircuitState, InvalidCircuitState, RecordResult,
};
pub use fixed_window::{FixedWindow, FixedWindowParams, FixedWindowState};
pub use gate::{Decision, Gate};
pub use gcra::{Gcra, GcraParams};
#[cfg(feature = "std")]
pub use keyed::KeyedGcra;
pub use token_bucket::{TokenBucket, TokenBucketParams, TokenBucketState};
