//! The gem's policy `Data` classes, resolved once at init and pinned: read
//! from Ruby by exact class and re-validated through the core, and built
//! natively from what the core holds.

use std::num::NonZeroU64;

use magnus::{Error, IntoValue, RArray, RClass, RModule, RStruct, Ruby, Value, prelude::*};
use matryona_machines::ruby::{Class, duration, exact_fields, nanoseconds, positive};
use throttle_machines::{FixedWindowPolicy, GcraPolicy, TokenBucketPolicy};

/// Every `Data` class of the gem, as resolved at init.
pub struct Classes {
    gcra: Class,
    token_bucket: Class,
    fixed_window: Class,
}

matryona_machines::registry! {
    static CLASSES: Classes = "throttle_machines";
    fn classes;
}

pub fn resolve(ruby: &Ruby, module: RModule) -> Result<(), Error> {
    let class = |name| Class::resolve(ruby, module, name);
    let classes = Classes {
        gcra: class("GcraPolicy")?,
        token_bucket: class("TokenBucketPolicy")?,
        fixed_window: class("FixedWindowPolicy")?,
    };
    CLASSES.set(ruby, classes).map(drop)
}

fn range_error(ruby: &Ruby, message: &'static str) -> Error {
    Error::new(ruby.exception_range_error(), message)
}

/// A frozen instance of `class` holding `members`, in order: all
/// `Data#initialize` does past the check, which the core's own values need
/// not repeat, so no Ruby code runs.
fn build<const N: usize>(class: RClass, members: [Value; N]) -> Result<Value, Error> {
    let instance = RStruct::try_convert(class.obj_alloc()?)?;
    for (index, member) in members.into_iter().enumerate() {
        instance.aset(index, member)?;
    }
    instance.freeze();
    Ok(instance.as_value())
}

const ZERO_INTERVAL: &str = "emission_interval must be positive";
const ZERO_REFILL: &str = "refill_every must be positive";
const ZERO_WINDOW: &str = "window must be positive";
const ZERO_PERIOD: &str = "period must be positive";
const BURST: &str = "the burst ceiling (delay_tolerance + emission_interval) must fit a Duration \
                     and hold at most 2**64-1 emission intervals";

fn gcra_policy(ruby: &Ruby, interval: Value, tolerance: Value) -> Result<GcraPolicy, Error> {
    let interval = duration(interval, "emission_interval")?;
    let tolerance = duration(tolerance, "delay_tolerance")?;
    GcraPolicy::new(interval, tolerance).ok_or_else(|| {
        range_error(
            ruby,
            if interval.is_zero() {
                ZERO_INTERVAL
            } else {
                BURST
            },
        )
    })
}

fn token_bucket_policy(
    ruby: &Ruby,
    capacity: Value,
    refill_every: Value,
) -> Result<TokenBucketPolicy, Error> {
    let capacity = positive::<NonZeroU64>(capacity, "capacity")?;
    let refill_every = duration(refill_every, "refill_every")?;
    TokenBucketPolicy::new(capacity, refill_every).ok_or_else(|| range_error(ruby, ZERO_REFILL))
}

fn fixed_window_policy(
    ruby: &Ruby,
    window: Value,
    limit: Value,
) -> Result<FixedWindowPolicy, Error> {
    let window = duration(window, "window")?;
    let limit = positive::<NonZeroU64>(limit, "limit")?;
    FixedWindowPolicy::new(window, limit).ok_or_else(|| range_error(ruby, ZERO_WINDOW))
}

/// `__gcra_policy`: what `GcraPolicy::new` accepts.
pub fn check_gcra(ruby: &Ruby, interval: Value, tolerance: Value) -> Result<(), Error> {
    gcra_policy(ruby, interval, tolerance).map(drop)
}

/// `__token_bucket_policy`: what `TokenBucketPolicy::new` accepts.
pub fn check_token_bucket(ruby: &Ruby, capacity: Value, refill: Value) -> Result<(), Error> {
    token_bucket_policy(ruby, capacity, refill).map(drop)
}

/// `__fixed_window_policy`: what `FixedWindowPolicy::new` accepts.
pub fn check_fixed_window(ruby: &Ruby, window: Value, limit: Value) -> Result<(), Error> {
    fixed_window_policy(ruby, window, limit).map(drop)
}

/// `__gcra_per`: the two spans `GcraPolicy::per` answers, as an Array.
pub fn gcra_per(ruby: &Ruby, period: Value, limit: Value, burst: Value) -> Result<RArray, Error> {
    let period = duration(period, "period")?;
    let limit = positive::<NonZeroU64>(limit, "limit")?;
    let burst = positive::<NonZeroU64>(burst, "burst")?;
    let policy = GcraPolicy::per(period, limit, burst)
        .ok_or_else(|| range_error(ruby, if period.is_zero() { ZERO_PERIOD } else { BURST }))?;
    // `per` can answer a tolerance past what a policy span accepts back.
    let tolerance = u64::try_from(policy.delay_tolerance().as_nanos())
        .map_err(|_| range_error(ruby, "delay_tolerance must fit in 0..=2**64-1 nanoseconds"))?;
    Ok(ruby.ary_new_from_values(&[
        nanoseconds(ruby, policy.emission_interval()).as_value(),
        tolerance.into_value_with(ruby),
    ]))
}

/// `__token_bucket_per`: the capacity and refill span
/// `TokenBucketPolicy::per` answers, as an Array.
pub fn token_bucket_per(ruby: &Ruby, period: Value, limit: Value) -> Result<RArray, Error> {
    let period = duration(period, "period")?;
    let limit = positive::<NonZeroU64>(limit, "limit")?;
    let policy =
        TokenBucketPolicy::per(period, limit).ok_or_else(|| range_error(ruby, ZERO_PERIOD))?;
    Ok(ruby.ary_new_from_values(&[
        policy.capacity().get().into_value_with(ruby),
        nanoseconds(ruby, policy.refill_every()).as_value(),
    ]))
}

/// Exactly a `GcraPolicy`, its fields read from the struct and validated
/// again (`Marshal.load` skips `initialize`).
pub fn read_gcra(ruby: &Ruby, value: Value) -> Result<GcraPolicy, Error> {
    let class = classes(ruby)?.gcra.get(ruby);
    let [interval, tolerance] = exact_fields(
        ruby,
        value,
        class,
        "expected a ThrottleMachines::GcraPolicy",
    )?;
    gcra_policy(ruby, interval, tolerance)
}

/// Exactly a `TokenBucketPolicy`, as [`read_gcra`].
pub fn read_token_bucket(ruby: &Ruby, value: Value) -> Result<TokenBucketPolicy, Error> {
    let class = classes(ruby)?.token_bucket.get(ruby);
    let [capacity, refill] = exact_fields(
        ruby,
        value,
        class,
        "expected a ThrottleMachines::TokenBucketPolicy",
    )?;
    token_bucket_policy(ruby, capacity, refill)
}

/// Exactly a `FixedWindowPolicy`, as [`read_gcra`].
pub fn read_fixed_window(ruby: &Ruby, value: Value) -> Result<FixedWindowPolicy, Error> {
    let class = classes(ruby)?.fixed_window.get(ruby);
    let [window, limit] = exact_fields(
        ruby,
        value,
        class,
        "expected a ThrottleMachines::FixedWindowPolicy",
    )?;
    fixed_window_policy(ruby, window, limit)
}

pub fn gcra_value(ruby: &Ruby, policy: GcraPolicy) -> Result<Value, Error> {
    let members = [
        nanoseconds(ruby, policy.emission_interval()).as_value(),
        nanoseconds(ruby, policy.delay_tolerance()).as_value(),
    ];
    build(classes(ruby)?.gcra.get(ruby), members)
}

pub fn token_bucket_value(ruby: &Ruby, policy: TokenBucketPolicy) -> Result<Value, Error> {
    let members = [
        policy.capacity().get().into_value_with(ruby),
        nanoseconds(ruby, policy.refill_every()).as_value(),
    ];
    build(classes(ruby)?.token_bucket.get(ruby), members)
}

pub fn fixed_window_value(ruby: &Ruby, policy: FixedWindowPolicy) -> Result<Value, Error> {
    let members = [
        nanoseconds(ruby, policy.window()).as_value(),
        policy.limit().get().into_value_with(ruby),
    ];
    build(classes(ruby)?.fixed_window.get(ruby), members)
}
