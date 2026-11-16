# throttle-machines

Rate limiting on a clock you supply. `no_std`, allocation-free, no `unsafe`;
the crate reads no clock and does no I/O. `now` is a `core::time::Duration`
since an epoch you pick, and so is every span.

## Algorithms

Each limiter is a small `Copy` value, a validated policy plus the state it
has reached, behind the shared [`Gate`] contract:

- **GCRA** (`Gcra`, `GcraPolicy`): one call per emission interval, with a
  delay tolerance for bursts. Smooth and exact.
- **Token bucket** (`TokenBucket`, `TokenBucketPolicy`): a burst of
  `capacity`, one token earned every `refill_every`.
- **Fixed window** (`FixedWindow`, `FixedWindowPolicy`): `limit` calls per
  window.

`check(now)` admits one call and answers exactly how many more the gate
would admit at the same instant, or a `Refusal`, which changes nothing:
`Throttled`, or for GCRA `Overflow` when the admission would push the TAT
past `Duration::MAX`. `peek(now)` answers the same without consuming,
`retry_after(now)` how long until the next admission (`Duration::MAX` when
no instant a `Duration` holds admits one), and `refund()` gives one
admission back. Nothing saturates into a count: a window or refill due past
`Duration::MAX` is never due.

Policies are built with `new`, which answers `None` for a value the limiter
cannot honour (a zero interval, refill or window; a GCRA burst ceiling,
`delay_tolerance + emission_interval`, past `Duration::MAX` or holding more
than `u64::MAX` intervals, which no `u64` count could answer), or with `per(period,
limit, ..)`, which spreads `limit` calls over `period`, rounding the interval
up to the nanosecond so the rate never exceeds the one asked for.

```rust
use core::num::NonZeroU64;
use core::time::Duration;
use throttle_machines::{Gate, Gcra, GcraPolicy, Refusal};

// 10 calls per second, bursts of 3.
let ten = NonZeroU64::new(10).unwrap();
let policy = GcraPolicy::per(Duration::from_secs(1), ten, NonZeroU64::new(3).unwrap()).unwrap();
let mut gcra = Gcra::new(policy);

let now = Duration::from_secs(60);
assert_eq!(gcra.check(now), Ok(2));
assert_eq!(gcra.check(now), Ok(1));
assert_eq!(gcra.check(now), Ok(0));
assert_eq!(gcra.check(now), Err(Refusal::Throttled));
assert_eq!(gcra.retry_after(now), Duration::from_millis(100));
```

A caller that keeps state elsewhere between calls (a database row, a cache
entry) reads it back with `tat()`, `tokens()`/`refilled_at()` or
`count()`/`window_start()` and resumes with `restored`.

## Per-key limiting

The `std` feature adds `KeyedGcra`, which holds a TAT per key in a sharded,
mutex-guarded map and evicts keys once they have fully recovered.

Each shard holds at most `max_keys_per_shard` keys (4096 by default, 65536
with the default 16 shards). A full shard first reclaims recovered keys, in
batches: it sweeps once an eighth of it could have recovered, and refuses
untracked keys with `Refusal::Full` until then without allocating. Tracked
keys keep their limits; free slots in other shards are not borrowed.
`evict_at` is a cleanup trigger after admissions, not the cap; `evict(now)`
reclaims every recovered key whenever it is called. `peek` never reclaims.

`refund(key, now)` gives back one admission `check` granted, for calls that
spend several limiters and must be admitted by all of them or none.

The cap bounds entry count, not key length: bound identities at ingress when
they are attacker-controlled.

```rust
# #[cfg(feature = "std")] {
use core::num::NonZeroU64;
use std::time::{Duration, Instant};
use throttle_machines::{GcraPolicy, KeyedGcra};

let ten = NonZeroU64::new(10).unwrap();
let policy = GcraPolicy::per(Duration::from_secs(1), ten, NonZeroU64::new(3).unwrap()).unwrap();
let limiter = KeyedGcra::<String>::new(policy);

let epoch = Instant::now();
assert_eq!(limiter.check("203.0.113.7", epoch.elapsed()), Ok(2));
# }
```

```toml
[dependencies]
throttle-machines = { version = ">=0.6", features = ["std"] }
```

## License

MIT

[`Gate`]: https://docs.rs/throttle-machines/latest/throttle_machines/trait.Gate.html
