//! Thin binding to the throttle-machines gates.
//!
//! Each gate is a wrapped core value; its answers are only Integers, Symbols
//! and `nil`, so mutating calls change it in place, frozen checked first.
//!
//! Every `now` is read over the whole `Duration` range (matryona's
//! `instant`), so any instant a gate returns (a GCRA `tat` is `now` plus an
//! interval, past 2**64-1 nanoseconds) reads back.
mod init;
mod values;

use std::cell::RefCell;
use std::time::Duration;

use magnus::{Error, Integer, IntoValue, Ruby, Value, typed_data::Obj, value::ReprValue};
use matryona_machines::ruby::{Symbols, instant, integer, nanoseconds};
use throttle_machines::{
    FixedWindow as FixedWindowCore, Gate, Gcra as GcraCore, Refusal, TokenBucket as TokenBucketCore,
};

matryona_machines::symbols! {
    /// A refusal as its Symbol: the snake case of the core variant. The
    /// gates never answer `:full`; only the core's `KeyedGcra` does. Only
    /// GCRA answers `:overflow`.
    Refusals for Refusal as "refusal" {
        Throttled => "throttled",
        Full => "full",
        Overflow => "overflow",
    }
}

/// An honoured count as an Integer, a refusal as its Symbol.
fn answer(ruby: &Ruby, decided: Result<u64, Refusal>) -> Value {
    match decided {
        Ok(count) => count.into_value_with(ruby),
        Err(refused) => Refusals::symbol(ruby, refused).as_value(),
    }
}

fn now_of(now: Value) -> Result<Duration, Error> {
    instant(now, "now")
}

fn check<G: Gate>(
    ruby: &Ruby,
    this: impl ReprValue,
    cell: &RefCell<G>,
    now: Value,
) -> Result<Value, Error> {
    this.check_frozen()?;
    let now = now_of(now)?;
    let decided = cell.borrow_mut().check(now);
    Ok(answer(ruby, decided))
}

fn peek<G: Gate>(ruby: &Ruby, cell: &RefCell<G>, now: Value) -> Result<Value, Error> {
    let now = now_of(now)?;
    let decided = cell.borrow().peek(now);
    Ok(answer(ruby, decided))
}

fn retry_after<G: Gate>(ruby: &Ruby, cell: &RefCell<G>, now: Value) -> Result<Integer, Error> {
    let now = now_of(now)?;
    let wait = cell.borrow().retry_after(now);
    Ok(nanoseconds(ruby, wait))
}

fn refund<G: Gate>(this: impl ReprValue, cell: &RefCell<G>) -> Result<(), Error> {
    this.check_frozen()?;
    cell.borrow_mut().refund();
    Ok(())
}

#[magnus::wrap(class = "ThrottleMachines::Gcra", free_immediately, size)]
struct Gcra {
    core: RefCell<GcraCore>,
}

impl Gcra {
    fn new(ruby: &Ruby, policy: Value) -> Result<Self, Error> {
        let policy = values::read_gcra(ruby, policy)?;
        Ok(Self::from(GcraCore::new(policy)))
    }

    fn restored(ruby: &Ruby, policy: Value, tat: Value) -> Result<Self, Error> {
        let policy = values::read_gcra(ruby, policy)?;
        let tat = instant(tat, "tat")?;
        Ok(Self::from(GcraCore::restored(policy, tat)))
    }

    const fn from(core: GcraCore) -> Self {
        Self {
            core: RefCell::new(core),
        }
    }

    fn check(ruby: &Ruby, this: Obj<Self>, now: Value) -> Result<Value, Error> {
        check(ruby, this, &this.core, now)
    }

    fn peek(ruby: &Ruby, this: &Self, now: Value) -> Result<Value, Error> {
        peek(ruby, &this.core, now)
    }

    fn retry_after(ruby: &Ruby, this: &Self, now: Value) -> Result<Integer, Error> {
        retry_after(ruby, &this.core, now)
    }

    fn refund(this: Obj<Self>) -> Result<(), Error> {
        refund(this, &this.core)
    }

    fn policy(ruby: &Ruby, this: &Self) -> Result<Value, Error> {
        let policy = this.core.borrow().policy();
        values::gcra_value(ruby, policy)
    }

    fn tat(ruby: &Ruby, this: &Self) -> Integer {
        nanoseconds(ruby, this.core.borrow().tat())
    }
}

#[magnus::wrap(class = "ThrottleMachines::TokenBucket", free_immediately, size)]
struct TokenBucket {
    core: RefCell<TokenBucketCore>,
}

impl TokenBucket {
    fn new(ruby: &Ruby, policy: Value) -> Result<Self, Error> {
        let policy = values::read_token_bucket(ruby, policy)?;
        Ok(Self::from(TokenBucketCore::new(policy)))
    }

    /// Raises `RangeError` for more tokens than the capacity.
    fn restored(
        ruby: &Ruby,
        policy: Value,
        tokens: Value,
        refilled_at: Value,
    ) -> Result<Self, Error> {
        let policy = values::read_token_bucket(ruby, policy)?;
        let tokens = integer::<u64>(tokens, "tokens")?;
        let refilled_at = instant(refilled_at, "refilled_at")?;
        TokenBucketCore::restored(policy, tokens, refilled_at)
            .map(Self::from)
            .ok_or_else(|| {
                Error::new(
                    ruby.exception_range_error(),
                    "tokens must not exceed the capacity",
                )
            })
    }

    const fn from(core: TokenBucketCore) -> Self {
        Self {
            core: RefCell::new(core),
        }
    }

    fn check(ruby: &Ruby, this: Obj<Self>, now: Value) -> Result<Value, Error> {
        check(ruby, this, &this.core, now)
    }

    fn peek(ruby: &Ruby, this: &Self, now: Value) -> Result<Value, Error> {
        peek(ruby, &this.core, now)
    }

    fn retry_after(ruby: &Ruby, this: &Self, now: Value) -> Result<Integer, Error> {
        retry_after(ruby, &this.core, now)
    }

    fn refund(this: Obj<Self>) -> Result<(), Error> {
        refund(this, &this.core)
    }

    fn policy(ruby: &Ruby, this: &Self) -> Result<Value, Error> {
        let policy = this.core.borrow().policy();
        values::token_bucket_value(ruby, policy)
    }

    fn tokens(&self) -> u64 {
        self.core.borrow().tokens()
    }

    fn refilled_at(ruby: &Ruby, this: &Self) -> Integer {
        nanoseconds(ruby, this.core.borrow().refilled_at())
    }
}

#[magnus::wrap(class = "ThrottleMachines::FixedWindow", free_immediately, size)]
struct FixedWindow {
    core: RefCell<FixedWindowCore>,
}

impl FixedWindow {
    fn new(ruby: &Ruby, policy: Value) -> Result<Self, Error> {
        let policy = values::read_fixed_window(ruby, policy)?;
        Ok(Self::from(FixedWindowCore::new(policy)))
    }

    /// Raises `RangeError` for a count past the limit.
    fn restored(
        ruby: &Ruby,
        policy: Value,
        count: Value,
        window_start: Value,
    ) -> Result<Self, Error> {
        let policy = values::read_fixed_window(ruby, policy)?;
        let count = integer::<u64>(count, "count")?;
        let window_start = instant(window_start, "window_start")?;
        FixedWindowCore::restored(policy, count, window_start)
            .map(Self::from)
            .ok_or_else(|| {
                Error::new(
                    ruby.exception_range_error(),
                    "count must not exceed the limit",
                )
            })
    }

    const fn from(core: FixedWindowCore) -> Self {
        Self {
            core: RefCell::new(core),
        }
    }

    fn check(ruby: &Ruby, this: Obj<Self>, now: Value) -> Result<Value, Error> {
        check(ruby, this, &this.core, now)
    }

    fn peek(ruby: &Ruby, this: &Self, now: Value) -> Result<Value, Error> {
        peek(ruby, &this.core, now)
    }

    fn retry_after(ruby: &Ruby, this: &Self, now: Value) -> Result<Integer, Error> {
        retry_after(ruby, &this.core, now)
    }

    fn refund(this: Obj<Self>) -> Result<(), Error> {
        refund(this, &this.core)
    }

    fn policy(ruby: &Ruby, this: &Self) -> Result<Value, Error> {
        let policy = this.core.borrow().policy();
        values::fixed_window_value(ruby, policy)
    }

    fn count(&self) -> u64 {
        self.core.borrow().count()
    }

    fn window_start(ruby: &Ruby, this: &Self) -> Integer {
        nanoseconds(ruby, this.core.borrow().window_start())
    }
}
