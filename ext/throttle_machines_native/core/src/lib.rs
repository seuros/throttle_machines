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

#![cfg_attr(not(feature = "std"), no_std)]

pub mod circuit_breaker;
pub mod fixed_window;
pub mod gate;
pub mod gcra;
pub mod token_bucket;

pub use circuit_breaker::{BreakerParams, BreakerState, CircuitBreaker, CircuitState, RecordResult};
pub use fixed_window::{FixedWindow, FixedWindowParams, FixedWindowState};
pub use gate::{Decision, Gate};
pub use gcra::{Gcra, GcraParams};
pub use token_bucket::{TokenBucket, TokenBucketParams, TokenBucketState};
