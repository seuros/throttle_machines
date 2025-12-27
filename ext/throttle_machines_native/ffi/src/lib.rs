//! Ruby FFI bindings for throttle-machines rate limiting algorithms.

use magnus::{function, prelude::*, Ruby};
use throttle_machines::{fixed_window, gcra, token_bucket};

/// GCRA rate limit check.
///
/// Returns (allowed, new_tat, retry_after) tuple.
fn gcra_check(
    tat: f64,
    now: f64,
    emission_interval: f64,
    delay_tolerance: f64,
) -> (bool, f64, f64) {
    let result = gcra::check(tat, now, emission_interval, delay_tolerance);
    (result.allowed, result.new_tat, result.retry_after)
}

/// GCRA peek (non-consuming check).
///
/// Returns (allowed, tat, retry_after) tuple.
fn gcra_peek(tat: f64, now: f64, delay_tolerance: f64) -> (bool, f64, f64) {
    let result = gcra::peek(tat, now, delay_tolerance);
    (result.allowed, result.new_tat, result.retry_after)
}

/// Token bucket rate limit check.
///
/// Returns (allowed, new_tokens, retry_after) tuple.
fn token_bucket_check(
    tokens: f64,
    last_refill: f64,
    now: f64,
    capacity: f64,
    refill_rate: f64,
) -> (bool, f64, f64) {
    let result = token_bucket::check(tokens, last_refill, now, capacity, refill_rate);
    (result.allowed, result.new_tokens, result.retry_after)
}

/// Token bucket peek (non-consuming check).
///
/// Returns (allowed, tokens, retry_after) tuple.
fn token_bucket_peek(
    tokens: f64,
    last_refill: f64,
    now: f64,
    capacity: f64,
    refill_rate: f64,
) -> (bool, f64, f64) {
    let result = token_bucket::peek(tokens, last_refill, now, capacity, refill_rate);
    (result.allowed, result.new_tokens, result.retry_after)
}

/// Fixed window rate limit check.
///
/// Returns (allowed, new_count, retry_after) tuple.
fn fixed_window_check(
    count: u64,
    window_start: f64,
    now: f64,
    window_size: f64,
    limit: u64,
) -> (bool, u64, f64) {
    let result = fixed_window::check(count, window_start, now, window_size, limit);
    (result.allowed, result.new_count, result.retry_after)
}

/// Fixed window peek (non-consuming check).
///
/// Returns (allowed, count, retry_after) tuple.
fn fixed_window_peek(
    count: u64,
    window_start: f64,
    now: f64,
    window_size: f64,
    limit: u64,
) -> (bool, u64, f64) {
    let result = fixed_window::peek(count, window_start, now, window_size, limit);
    (result.allowed, result.new_count, result.retry_after)
}

/// Fixed window remaining calculation.
fn fixed_window_remaining(count: u64, limit: u64) -> u64 {
    fixed_window::remaining(count, limit)
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), magnus::Error> {
    let module = ruby.define_module("ThrottleMachinesNative")?;

    // GCRA functions
    module.define_singleton_method("gcra_check", function!(gcra_check, 4))?;
    module.define_singleton_method("gcra_peek", function!(gcra_peek, 3))?;

    // Token bucket functions
    module.define_singleton_method("token_bucket_check", function!(token_bucket_check, 5))?;
    module.define_singleton_method("token_bucket_peek", function!(token_bucket_peek, 5))?;

    // Fixed window functions
    module.define_singleton_method("fixed_window_check", function!(fixed_window_check, 5))?;
    module.define_singleton_method("fixed_window_peek", function!(fixed_window_peek, 5))?;
    module.define_singleton_method(
        "fixed_window_remaining",
        function!(fixed_window_remaining, 2),
    )?;

    Ok(())
}
