# throttle-machines

Rate limiting and circuit breaking as pure functions over caller-held state.
No clocks, no locks, no allocation: you store the state, pass it in with the
current time, and get a decision plus the next state back.

## Algorithms

Every algorithm implements the [`Gate`] trait (`check` consumes, `peek` doesn't):

- **GCRA** (Generic Cell Rate Algorithm): smooth, precise per-request spacing.
- **Token Bucket**: burst capacity with a steady refill rate.
- **Fixed Window**: a counter per window.
- **Circuit Breaker**: closed / open / half-open admission, with `record` to
  fold call outcomes back in.

## Usage

```rust
use throttle_machines::gate::Gate;
use throttle_machines::gcra::{Gcra, GcraParams};

// 10 requests per second, no burst allowance.
let params = GcraParams { emission_interval: 0.1, delay_tolerance: 0.0 };

let mut tat = 0.0; // Theoretical Arrival Time, stored by the caller
let first = Gcra::check(tat, 1.0, params);
assert!(first.allowed);
tat = first.state;

let second = Gcra::check(tat, 1.0, params);
assert!(!second.allowed);
assert!(second.retry_after > 0.0);
```

## no_std

The crate is `no_std` with the default `std` feature disabled:

```toml
[dependencies]
throttle-machines = { version = "0.2", default-features = false }
```

## License

MIT

[`Gate`]: https://docs.rs/throttle-machines/latest/throttle_machines/gate/trait.Gate.html
