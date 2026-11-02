# throttle-machines

Rate limiting as pure functions over caller-held state.
No clocks, no locks, no allocation: you store the state, pass it in with the
current time, and get a decision plus the next state back.

## Algorithms

Every algorithm implements the [`Gate`] trait (`check` consumes, `peek` doesn't):

- **GCRA** (Generic Cell Rate Algorithm): smooth, precise per-request spacing.
- **Token Bucket**: burst capacity with a steady refill rate.
- **Fixed Window**: a counter per window.

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

### Per-key limiting

With `std`, `KeyedGcra` holds the per-key state for you: a sharded map on a
monotonic clock that evicts keys once they have fully recovered.

Storage is capped at **4096 keys per shard** by default (at most 65536 keys
with the default 16 shards). Configure it with
`KeyedGcra::new(params).max_keys_per_shard(1024)`. A full shard first reclaims
recovered keys, in batches: it sweeps once an eighth of it could have
recovered, and refuses unknown identities without allocating state until then.
Existing identities keep their rate limits; free slots in other shards are
not borrowed. Zero rejects all identities.

`evict_at` is only a cleanup trigger, not the cap. Automatic sweeps wait until
an eighth of the shard could have recovered, so neither busy keys nor a
rejected identity spray make every check rescan the shard. `evict` reclaims
every recovered key whenever it is called. `peek` also respects the cap and may reclaim recovered
keys, but never consumes an admission. Capacity refusals have state `0.0` and
a retry hint based on the next possible recovery (not a reservation).

`refund` gives back one admission `check` granted, for requests that spend
several limiters and must be admitted by all of them or none: check each, and
refund the ones that admitted when a later one refuses.

The cap bounds entry count, not arbitrary key byte lengths. Bound identity
length at ingress as well when keys are attacker-controlled.

```rust
use throttle_machines::{GcraParams, KeyedGcra};

// 10 requests per second per client, bursts of 3.
let limiter = KeyedGcra::<String>::new(GcraParams::from_rate(10.0, 3));

let decision = limiter.check("203.0.113.7");
assert!(decision.allowed);
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
