# throttle-machines

High-performance rate limiting algorithms for Rust.

## Algorithms

- **GCRA** (Generic Cell Rate Algorithm) - Smooth, precise per-request timing
- **Token Bucket** - Allows burst capacity with steady refill rate
- **Fixed Window** - Simple counter with TTL in current window

## Usage

```rust
use throttle_machines::gcra;

let result = gcra::check(
    0.0,    // current TAT (Theoretical Arrival Time)
    1.0,    // current time
    0.1,    // emission_interval (period / limit)
    0.0,    // delay_tolerance (for burst allowance)
);

if result.allowed {
    println!("Request allowed, new TAT: {}", result.new_tat);
} else {
    println!("Rate limited, retry after: {}s", result.retry_after);
}
```

## no_std Support

This crate is `no_std` compatible when the `std` feature is disabled:

```toml
[dependencies]
throttle-machines = { version = "0.1", default-features = false }
```

## License

MIT
