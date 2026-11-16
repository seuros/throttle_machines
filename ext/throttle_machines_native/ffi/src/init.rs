//! Private native entry point.
use magnus::{Error, Ruby, function, method, prelude::*};
use matryona_machines::ruby::Class;

use crate::{FixedWindow, Gcra, TokenBucket, values};

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("ThrottleMachines")?;
    values::resolve(ruby, module)?;
    // Validation hooks for the Data values; lib/ makes them private.
    module.define_singleton_method("__gcra_policy", function!(values::check_gcra, 2))?;
    module.define_singleton_method(
        "__token_bucket_policy",
        function!(values::check_token_bucket, 2),
    )?;
    module.define_singleton_method(
        "__fixed_window_policy",
        function!(values::check_fixed_window, 2),
    )?;
    module.define_singleton_method("__gcra_per", function!(values::gcra_per, 3))?;
    module.define_singleton_method("__token_bucket_per", function!(values::token_bucket_per, 2))?;

    let gcra = module.define_class("Gcra", ruby.class_object())?;
    gcra.undef_default_alloc_func();
    gcra.define_singleton_method("new", function!(Gcra::new, 1))?;
    gcra.define_singleton_method("restored", function!(Gcra::restored, 2))?;
    gcra.define_method("check", method!(Gcra::check, 1))?;
    gcra.define_method("peek", method!(Gcra::peek, 1))?;
    gcra.define_method("retry_after", method!(Gcra::retry_after, 1))?;
    gcra.define_method("refund", method!(Gcra::refund, 0))?;
    gcra.define_method("policy", method!(Gcra::policy, 0))?;
    gcra.define_method("tat", method!(Gcra::tat, 0))?;
    // Each `new` answers a wrapped gate: its class is fixed now, so building
    // one never looks it up by name.
    Class::pin_wrapped::<Gcra>(ruby, gcra)?;

    let bucket = module.define_class("TokenBucket", ruby.class_object())?;
    bucket.undef_default_alloc_func();
    bucket.define_singleton_method("new", function!(TokenBucket::new, 1))?;
    bucket.define_singleton_method("restored", function!(TokenBucket::restored, 3))?;
    bucket.define_method("check", method!(TokenBucket::check, 1))?;
    bucket.define_method("peek", method!(TokenBucket::peek, 1))?;
    bucket.define_method("retry_after", method!(TokenBucket::retry_after, 1))?;
    bucket.define_method("refund", method!(TokenBucket::refund, 0))?;
    bucket.define_method("policy", method!(TokenBucket::policy, 0))?;
    bucket.define_method("tokens", method!(TokenBucket::tokens, 0))?;
    bucket.define_method("refilled_at", method!(TokenBucket::refilled_at, 0))?;
    Class::pin_wrapped::<TokenBucket>(ruby, bucket)?;

    let window = module.define_class("FixedWindow", ruby.class_object())?;
    window.undef_default_alloc_func();
    window.define_singleton_method("new", function!(FixedWindow::new, 1))?;
    window.define_singleton_method("restored", function!(FixedWindow::restored, 3))?;
    window.define_method("check", method!(FixedWindow::check, 1))?;
    window.define_method("peek", method!(FixedWindow::peek, 1))?;
    window.define_method("retry_after", method!(FixedWindow::retry_after, 1))?;
    window.define_method("refund", method!(FixedWindow::refund, 0))?;
    window.define_method("policy", method!(FixedWindow::policy, 0))?;
    window.define_method("count", method!(FixedWindow::count, 0))?;
    window.define_method("window_start", method!(FixedWindow::window_start, 0))?;
    Class::pin_wrapped::<FixedWindow>(ruby, window).map(drop)
}
