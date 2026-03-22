//! Rate limiting algorithms for high-performance applications.
//!
//! This crate provides three rate limiting algorithms:
//! - GCRA (Generic Cell Rate Algorithm)
//! - Token Bucket
//! - Fixed Window
//!
//! All algorithms are `no_std` compatible when the `std` feature is disabled.

#![cfg_attr(not(feature = "std"), no_std)]

pub mod fixed_window;
pub mod gcra;
pub mod token_bucket;

pub use fixed_window::FixedWindowResult;
pub use gcra::GcraResult;
pub use token_bucket::TokenBucketResult;
