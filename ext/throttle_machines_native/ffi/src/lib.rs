//! Ruby FFI bindings for throttle-machines rate limiting algorithms.
//!
//! Admission checks return a `ThrottleMachinesNative::Decision`
//! (`Data.define(:allowed, :state, :retry_after)`), frozen and holding only
//! shareable values (booleans, integers, floats), so it is Ractor-shareable,
//! and the extension itself is marked Ractor-safe.

use magnus::value::Opaque;
use magnus::{Error, IntoValue, RClass, RStruct, Ruby, Value, function, prelude::*};
use std::sync::OnceLock;
use throttle_machines::fixed_window::{FixedWindowParams, FixedWindowState};
use throttle_machines::gate::Gate;
use throttle_machines::gcra::GcraParams;
use throttle_machines::token_bucket::{TokenBucketParams, TokenBucketState};
use throttle_machines::{FixedWindow, Gcra, TokenBucket};

/// `ThrottleMachinesNative::Decision`, defined once in `init`.
static DECISION: OnceLock<Opaque<RClass>> = OnceLock::new();

/// `Decision` members, in the order [`decision`] fills them.
const DECISION_MEMBERS: (&str, &str, &str) = ("allowed", "state", "retry_after");

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

/// Instantiate one of our `Data` classes from its member values, in
/// declaration order, allocating nothing but the instance itself.
///
/// `Data#initialize` takes keywords only, so `new_instance` would need a
/// temporary `Hash` per call, plus a temporary `String` per key while magnus
/// interns it to a `Symbol`. Allocating, filling the members by position and
/// freezing is everything `Data#initialize` does, and yields an instance that
/// is `==`/`eql?` to the keyword-built one, frozen and Ractor-shareable. Both
/// classes are defined here, with no `initialize` override to skip.
fn new_data<const N: usize>(
    ruby: &Ruby,
    class: &OnceLock<Opaque<RClass>>,
    members: [Value; N],
) -> Result<Value, Error> {
    let instance = RStruct::try_convert(data_class(ruby, class)?.obj_alloc()?)?;
    for (index, value) in members.into_iter().enumerate() {
        instance.aset(index, value)?;
    }
    instance.freeze();
    Ok(instance.as_value())
}

/// Build a `Decision`. `state` is the algorithm's next state: a TAT, token
/// count, window count, or encoded breaker state.
fn decision(
    ruby: &Ruby,
    allowed: bool,
    state: impl IntoValue,
    retry_after: f64,
) -> Result<Value, Error> {
    new_data(
        ruby,
        &DECISION,
        [
            ruby.into_value(allowed),
            ruby.into_value(state),
            ruby.into_value(retry_after),
        ],
    )
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
const fn fixed_window_remaining(count: u64, limit: u64) -> u64 {
    FixedWindow::remaining(count, limit)
}

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
    #[allow(unsafe_code)]
    // SAFETY: called on the loading thread during extension initialisation.
    unsafe {
        rb_sys::rb_ext_ractor_safe(true);
    }

    let module = ruby.define_module("ThrottleMachinesNative")?;
    define_data_class(ruby, module, &DECISION, "Decision", DECISION_MEMBERS)?;

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
