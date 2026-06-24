//! Ruby FFI bindings for throttle-machines rate limiting algorithms.

use magnus::{Ruby, function, prelude::*};
use throttle_machines::circuit_breaker::{BreakerParams, BreakerState, CircuitState};
use throttle_machines::fixed_window::{FixedWindowParams, FixedWindowState};
use throttle_machines::gate::Gate;
use throttle_machines::gcra::GcraParams;
use throttle_machines::token_bucket::{TokenBucketParams, TokenBucketState};
use throttle_machines::{CircuitBreaker, FixedWindow, Gcra, TokenBucket};

/// GCRA rate limit check.
///
/// Returns (allowed, new_tat, retry_after) tuple.
fn gcra_check(
    tat: f64,
    now: f64,
    emission_interval: f64,
    delay_tolerance: f64,
) -> (bool, f64, f64) {
    let params = GcraParams {
        emission_interval,
        delay_tolerance,
    };
    let result = Gcra::check(tat, now, params);
    (result.allowed, result.state, result.retry_after)
}

/// GCRA peek (non-consuming check).
///
/// Returns (allowed, tat, retry_after) tuple.
fn gcra_peek(tat: f64, now: f64, delay_tolerance: f64) -> (bool, f64, f64) {
    // emission_interval is unused by peek; the TAT is not advanced.
    let params = GcraParams {
        emission_interval: 0.0,
        delay_tolerance,
    };
    let result = Gcra::peek(tat, now, params);
    (result.allowed, result.state, result.retry_after)
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
    let state = TokenBucketState { tokens, last_refill };
    let params = TokenBucketParams {
        capacity,
        refill_rate,
    };
    let result = TokenBucket::check(state, now, params);
    (result.allowed, result.state.tokens, result.retry_after)
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
    let state = TokenBucketState { tokens, last_refill };
    let params = TokenBucketParams {
        capacity,
        refill_rate,
    };
    let result = TokenBucket::peek(state, now, params);
    (result.allowed, result.state.tokens, result.retry_after)
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
    let state = FixedWindowState {
        count,
        window_start,
    };
    let params = FixedWindowParams { window_size, limit };
    let result = FixedWindow::check(state, now, params);
    (result.allowed, result.state.count, result.retry_after)
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
    let state = FixedWindowState {
        count,
        window_start,
    };
    let params = FixedWindowParams { window_size, limit };
    let result = FixedWindow::peek(state, now, params);
    (result.allowed, result.state.count, result.retry_after)
}

/// Fixed window remaining calculation.
fn fixed_window_remaining(count: u64, limit: u64) -> u64 {
    FixedWindow::remaining(count, limit)
}

/// Circuit breaker admission check.
///
/// `state` is encoded as Closed = 0, Open = 1, HalfOpen = 2.
/// Returns (allowed, new_state, retry_after) tuple.
fn circuit_breaker_check(
    state: u8,
    opened_at: f64,
    now: f64,
    reset_timeout: f64,
) -> (bool, u8, f64) {
    let breaker = BreakerState {
        state: CircuitState::from_u8(state),
        opened_at,
    };
    let result = CircuitBreaker::check(breaker, now, BreakerParams { reset_timeout });
    (result.allowed, result.state.state.to_u8(), result.retry_after)
}

/// Circuit breaker peek (non-transitioning admission check).
///
/// Returns (allowed, state, retry_after) tuple. Never moves an Open breaker
/// into the half-open probe window.
fn circuit_breaker_peek(state: u8, opened_at: f64, now: f64, reset_timeout: f64) -> (bool, u8, f64) {
    let breaker = BreakerState {
        state: CircuitState::from_u8(state),
        opened_at,
    };
    let result = CircuitBreaker::peek(breaker, now, BreakerParams { reset_timeout });
    (result.allowed, result.state.state.to_u8(), result.retry_after)
}

/// Circuit breaker outcome record.
///
/// Folds the result of a completed call back into the breaker state.
/// Returns (new_state, new_failures, opened_at) tuple.
fn circuit_breaker_record(
    state: u8,
    failures: u32,
    now: f64,
    success: bool,
    failure_threshold: u32,
) -> (u8, u32, f64) {
    let result = CircuitBreaker::record(
        CircuitState::from_u8(state),
        failures,
        now,
        success,
        failure_threshold,
    );
    (result.new_state.to_u8(), result.new_failures, result.opened_at)
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

    // Circuit breaker functions
    module.define_singleton_method("circuit_breaker_check", function!(circuit_breaker_check, 4))?;
    module.define_singleton_method("circuit_breaker_peek", function!(circuit_breaker_peek, 4))?;
    module.define_singleton_method(
        "circuit_breaker_record",
        function!(circuit_breaker_record, 5),
    )?;

    Ok(())
}
