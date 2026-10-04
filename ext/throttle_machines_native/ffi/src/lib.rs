//! Ruby FFI bindings for throttle-machines rate limiting algorithms.
//!
//! Admission checks return a `ThrottleMachinesNative::Decision`
//! (`Data.define(:allowed, :state, :retry_after)`); breaker outcome records
//! return a `ThrottleMachinesNative::Outcome`
//! (`Data.define(:state, :failures, :opened_at)`). Both are frozen and hold
//! only immediates, so they are Ractor-shareable, and the extension itself
//! is marked Ractor-safe.

use magnus::value::Opaque;
use magnus::{Error, IntoValue, RClass, Ruby, Value, function, kwargs, prelude::*};
use std::sync::OnceLock;
use throttle_machines::circuit_breaker::{BreakerParams, BreakerState, CircuitState};
use throttle_machines::fixed_window::{FixedWindowParams, FixedWindowState};
use throttle_machines::gate::Gate;
use throttle_machines::gcra::GcraParams;
use throttle_machines::token_bucket::{TokenBucketParams, TokenBucketState};
use throttle_machines::{CircuitBreaker, FixedWindow, Gcra, TokenBucket};

/// `ThrottleMachinesNative::Decision`, defined once in `init`.
static DECISION: OnceLock<Opaque<RClass>> = OnceLock::new();
/// `ThrottleMachinesNative::Outcome`, defined once in `init`.
static OUTCOME: OnceLock<Opaque<RClass>> = OnceLock::new();

fn data_class(ruby: &Ruby, class: &OnceLock<Opaque<RClass>>) -> Result<RClass, Error> {
    class
        .get()
        .map(|class| ruby.get_inner(*class))
        .ok_or_else(|| {
            Error::new(
                ruby.exception_runtime_error(),
                "ThrottleMachinesNative is not initialised",
            )
        })
}

/// Build a `Decision`. `state` is the algorithm's next state: a TAT, token
/// count, window count, or encoded breaker state.
fn decision(
    ruby: &Ruby,
    allowed: bool,
    state: impl IntoValue,
    retry_after: f64,
) -> Result<Value, Error> {
    // Data#initialize takes keywords only; `Data.new`'s positional form is
    // bypassed by rb_class_new_instance.
    data_class(ruby, &DECISION)?.new_instance((kwargs!(
        "allowed" => allowed,
        "state" => state,
        "retry_after" => retry_after
    ),))
}

/// GCRA rate limit check.
fn gcra_check(
    ruby: &Ruby,
    tat: f64,
    now: f64,
    emission_interval: f64,
    delay_tolerance: f64,
) -> Result<Value, Error> {
    let params = GcraParams {
        emission_interval,
        delay_tolerance,
    };
    let result = Gcra::check(tat, now, params);
    decision(ruby, result.allowed, result.state, result.retry_after)
}

/// GCRA peek (non-consuming check).
fn gcra_peek(ruby: &Ruby, tat: f64, now: f64, delay_tolerance: f64) -> Result<Value, Error> {
    // emission_interval is unused by peek; the TAT is not advanced.
    let params = GcraParams {
        emission_interval: 0.0,
        delay_tolerance,
    };
    let result = Gcra::peek(tat, now, params);
    decision(ruby, result.allowed, result.state, result.retry_after)
}

/// Token bucket rate limit check.
fn token_bucket_check(
    ruby: &Ruby,
    tokens: f64,
    last_refill: f64,
    now: f64,
    capacity: f64,
    refill_rate: f64,
) -> Result<Value, Error> {
    let state = TokenBucketState {
        tokens,
        last_refill,
    };
    let params = TokenBucketParams {
        capacity,
        refill_rate,
    };
    let result = TokenBucket::check(state, now, params);
    decision(
        ruby,
        result.allowed,
        result.state.tokens,
        result.retry_after,
    )
}

/// Token bucket peek (non-consuming check).
fn token_bucket_peek(
    ruby: &Ruby,
    tokens: f64,
    last_refill: f64,
    now: f64,
    capacity: f64,
    refill_rate: f64,
) -> Result<Value, Error> {
    let state = TokenBucketState {
        tokens,
        last_refill,
    };
    let params = TokenBucketParams {
        capacity,
        refill_rate,
    };
    let result = TokenBucket::peek(state, now, params);
    decision(
        ruby,
        result.allowed,
        result.state.tokens,
        result.retry_after,
    )
}

/// Fixed window rate limit check.
fn fixed_window_check(
    ruby: &Ruby,
    count: u64,
    window_start: f64,
    now: f64,
    window_size: f64,
    limit: u64,
) -> Result<Value, Error> {
    let state = FixedWindowState {
        count,
        window_start,
    };
    let params = FixedWindowParams { window_size, limit };
    let result = FixedWindow::check(state, now, params);
    decision(ruby, result.allowed, result.state.count, result.retry_after)
}

/// Fixed window peek (non-consuming check).
fn fixed_window_peek(
    ruby: &Ruby,
    count: u64,
    window_start: f64,
    now: f64,
    window_size: f64,
    limit: u64,
) -> Result<Value, Error> {
    let state = FixedWindowState {
        count,
        window_start,
    };
    let params = FixedWindowParams { window_size, limit };
    let result = FixedWindow::peek(state, now, params);
    decision(ruby, result.allowed, result.state.count, result.retry_after)
}

/// Fixed window remaining calculation.
fn fixed_window_remaining(count: u64, limit: u64) -> u64 {
    FixedWindow::remaining(count, limit)
}

/// Circuit breaker admission check.
///
/// `state` is encoded as Closed = 0, Open = 1, HalfOpen = 2.
fn circuit_breaker_check(
    ruby: &Ruby,
    state: u8,
    opened_at: f64,
    now: f64,
    reset_timeout: f64,
) -> Result<Value, Error> {
    let breaker = BreakerState {
        state: CircuitState::from_u8(state),
        opened_at,
    };
    let result = CircuitBreaker::check(breaker, now, BreakerParams { reset_timeout });
    decision(
        ruby,
        result.allowed,
        result.state.state.to_u8(),
        result.retry_after,
    )
}

/// Circuit breaker peek (non-transitioning admission check).
///
/// Never moves an Open breaker into the half-open probe window.
fn circuit_breaker_peek(
    ruby: &Ruby,
    state: u8,
    opened_at: f64,
    now: f64,
    reset_timeout: f64,
) -> Result<Value, Error> {
    let breaker = BreakerState {
        state: CircuitState::from_u8(state),
        opened_at,
    };
    let result = CircuitBreaker::peek(breaker, now, BreakerParams { reset_timeout });
    decision(
        ruby,
        result.allowed,
        result.state.state.to_u8(),
        result.retry_after,
    )
}

/// Circuit breaker outcome record.
///
/// Folds the result of a completed call back into the breaker state.
fn circuit_breaker_record(
    ruby: &Ruby,
    state: u8,
    failures: u32,
    now: f64,
    success: bool,
    failure_threshold: u32,
) -> Result<Value, Error> {
    let result = CircuitBreaker::record(
        CircuitState::from_u8(state),
        failures,
        now,
        success,
        failure_threshold,
    );
    data_class(ruby, &OUTCOME)?.new_instance((kwargs!(
        "state" => result.new_state.to_u8(),
        "failures" => result.new_failures,
        "opened_at" => result.opened_at
    ),))
}

/// Define a `Data` class under `module` and remember it for the functions.
fn define_data_class(
    ruby: &Ruby,
    module: magnus::RModule,
    slot: &OnceLock<Opaque<RClass>>,
    name: &str,
    members: (&str, &str, &str),
) -> Result<(), Error> {
    let class = ruby.define_data(None, members)?;
    module.const_set(name, class)?;
    slot.set(class.into()).map_err(|_| {
        Error::new(
            ruby.exception_runtime_error(),
            format!("ThrottleMachinesNative::{name} initialised twice"),
        )
    })
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    // Must precede every method definition: Ruby marks methods Ractor-safe as
    // they are defined. The only globals are the write-once class slots.
    // SAFETY: called on the loading thread during extension initialisation.
    unsafe { rb_sys::rb_ext_ractor_safe(true) };

    let module = ruby.define_module("ThrottleMachinesNative")?;
    define_data_class(
        ruby,
        module,
        &DECISION,
        "Decision",
        ("allowed", "state", "retry_after"),
    )?;
    define_data_class(
        ruby,
        module,
        &OUTCOME,
        "Outcome",
        ("state", "failures", "opened_at"),
    )?;

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
