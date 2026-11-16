# ThrottleMachines 🚀

> **Ultra-thin rate limiting for the cosmos** - Where every request has its own trajectory through spacetime

A precision-engineered Ruby rate limiting library built for interstellar traffic control.
Whether you're throttling API calls, AI requests, or quantum communications, ThrottleMachines ensures your systems maintain perfect orbital stability.

---

## 🌌 Navigation

* [🎯 Mission Control](docs/MISSION_CONTROL.md) - Quick start guide for captains
* [🛸 Spacecraft Manual](docs/SPACECRAFT_MANUAL.md) - Understanding the fleet (algorithms)
* [⚡ Warp Drive Configuration](docs/WARP_DRIVE.md) - Storage backends & performance
* [🛡️ Shield Protocols](docs/SHIELD_PROTOCOLS.md) - Circuit breakers & defensive systems
* [🌍 Planetary Integration](docs/PLANETARY_INTEGRATION.md) - Rails & Rack middleware
* [🔬 Space Lab](docs/SPACE_LAB.md) - Testing in zero gravity
* [📡 Telemetry](docs/TELEMETRY.md) - Monitoring & instrumentation
* [🎮 Command Examples](docs/COMMAND_EXAMPLES.md) - Real mission scenarios
* [📜 Mission Logs](docs/MISSION_LOGS.md) - Lessons from real incidents
* [🚀 Advanced Features](docs/ADVANCED_FEATURES.md) - Next-generation capabilities

---

## 🚀 Launch Sequence

```bash
# Add to your ship's Gemfile
gem 'throttle_machines'

# For warp drive capabilities (Redis storage)
gem 'redis'

# For planetary Rails integration
gem 'rails' # or just railties

# For fiber-safe async throttling
gem 'async'
```

Then initialize systems:
```bash
bundle install
```

---

## 🕰️ Ship's Clock

Every instant and span is **Integer nanoseconds**: periods, windows, TTLs,
`retry_after`, deadlines. `ThrottleMachines.monotonic_time` reads
`Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)`. No floats, no
seconds; HTTP `Retry-After` headers are the one place a wait becomes whole
seconds, rounded up.

```ruby
NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000
```

---

## 🎯 Quick Mission Brief

### Basic Throttling - The Photon Torpedo Approach

```ruby
# Simple rate limiting - like controlling photon torpedo launches
torpedo_limiter = ThrottleMachines.limiter("photon_launcher",
  limit: 10,       # 10 torpedoes
  period: 60 * NS  # per minute
)

# Check and consume approach
if torpedo_limiter.allow?
  torpedo_limiter.throttle!  # Consume one torpedo charge
  launch_torpedo!
else
  puts "Torpedo bay recharging... Please wait."
end

# OR use the exception approach
begin
  torpedo_limiter.throttle!
  launch_torpedo!
rescue ThrottleMachines::ThrottledError => e
  puts "Torpedo bay recharging... Retry after #{e.retry_after} ns"
end
```

### GCRA - The Federation Diplomatic Ship 🛸

```ruby
# GCRA: Like a diplomatic vessel that smoothly navigates traffic
# Instead of sudden stops, it gracefully manages flow
diplomatic_limiter = ThrottleMachines.limiter("federation_embassy",
  limit: 100,
  period: 60 * NS,
  algorithm: :gcra  # Generic Cell Rate Algorithm
)

# GCRA ensures smooth traffic - no thundering herds at your space dock!
```

### Block Form - Fire and Forget 🎯

```ruby
# Use the block form for automatic throttling
# This handles the throttle! and error handling for you
ThrottleMachines.limit("warp_drive", limit: 5, period: 60 * NS) do
  engage_warp_drive!  # This will be throttled automatically
end
# Raises ThrottledError if limit exceeded
```

### The Reactor Core - Native Gates 🔩

Under every limiter sits a `no_std` Rust core. Its gates are yours to drive
directly, on a clock you supply. Policies are frozen `Data` values validated
by the core (`TypeError` for the wrong type, `RangeError` for a value it
refuses); a gate answers exactly how many more calls it would admit at that
instant, or a refusal Symbol, which changes nothing: `:throttled`, or for
GCRA `:overflow` when an admission would push its TAT past the largest
instant (`(2**64 * 10**9) - 1` nanoseconds; `retry_after` then answers that
instant: never). A `GcraPolicy` whose burst ceiling holds more than
`2**64 - 1` emission intervals is a `RangeError`. `now` is read over that
whole range, so every instant a gate returns (a GCRA `tat` can pass
`2**64 - 1`) reads back.

```ruby
policy = ThrottleMachines::GcraPolicy.per(1 * NS, 10, 3) # 10/s, bursts of 3
gate = ThrottleMachines::Gcra.new(policy)
now = ThrottleMachines.monotonic_time

gate.check(now)       # => 2, then 1, then 0
gate.check(now)       # => :throttled (after the burst)
gate.retry_after(now) # => 100_000_000
gate.peek(now)        # non-consuming; gate.refund gives one back

bucket = ThrottleMachines::TokenBucket.new(ThrottleMachines::TokenBucketPolicy.new(5, 200_000_000))
window = ThrottleMachines::FixedWindow.new(ThrottleMachines::FixedWindowPolicy.new(60 * NS, 100))
```

State kept elsewhere resumes with `Gcra.restored(policy, tat)`,
`TokenBucket.restored(policy, tokens, refilled_at)` and
`FixedWindow.restored(policy, count, window_start)`.

### Retries and Breakers 🛡️

```ruby
backoff = ChronoMachines::Exponential.new(100_000_000, 2.0, 5 * NS, 1.0)

ThrottleMachines.control("hyperspace_relay") do
  limit rate: 10, per: 1 * NS
  break_on failures: 5, within: 60 * NS
  retry_on_failure backoff, 3
end.call { relay.transmit! }
```

---

## Bounded in-memory storage

The memory backend tracks at most **65536 entries**, shared across fixed-window
counters, GCRA states, and token buckets.

```ruby
ThrottleMachines.storage = ThrottleMachines::Storage::Memory.new(max_keys: 10_000)
```

When full, expired entries are reclaimed before admission. If no slot is
available, new identities are refused with `:full`; active identities are never evicted
to make room and can continue under their existing limits. Peeks also fail
closed for untrackable identities. Capacity refusals use a one-second retry
hint, not a reservation. At saturation, on-demand expiry scans run at most
once per second, even with `auto_cleanup: false`.

`max_keys` must be a non-negative Integer; zero denies all identities. For
direct storage callers, an untrackable fixed-window counter reads/increments
as `Storage::Base::UNTRACKED` (2**64) so it cannot pass a rate limit.

This bounds entry count, not bytes: also bound untrusted identity lengths.
Redis storage uses TTLs but has no application-level key cap; configure Redis
memory limits separately. Evicting active Redis keys can reset their limits.
Redis scripts read `now` from the server (`TIME`, whole microseconds, turned
into nanoseconds), so processes on any number of hosts can share one Redis
store; a step in the Redis host's clock is a step for every limit. Stored
instants count from a `TIME` second kept beside them and are rebased on each
write, which keeps the scripts' double arithmetic exact. GCRA state is a hash:
clear throttle keys written by a release that passed the caller's clock.

---

## Rails cache storage

`Storage::Cache` keeps fixed-window counters in any `ActiveSupport::Cache`
store, so limits share Solid Cache, Redis, or Memcached with the rest of the app
(and with `BreakerMachines::Storage::Cache`).

```ruby
ThrottleMachines.storage = ThrottleMachines::Storage::Cache.new(cache_store: Rails.cache)
# or, inside Rails: config.default_storage = :cache
```

Windows align to the Unix epoch and each one is its own cache entry, admitted
with a single atomic `increment`. On Solid Cache with PostgreSQL, the first
increments of a window can race and undercount by the number of concurrent
first requests.

It supports `:fixed_window` only; the cache API has no atomic read-modify-write
for GCRA or token buckets. A limiter built with an algorithm its storage lacks
raises `RangeError` on construction, for custom backends too.

When the store fails to count (an outage, `NullStore`), requests are admitted.
Pass `fail_closed: true` to throttle them instead. `clear` deletes only this
backend's keys and needs `delete_matched`; on Solid Cache and Memcached it
raises `ThrottleMachines::UnsupportedOperationError`, so reset single limiters
with `Limiter#reset!`.

---

## 🌠 The Ultra-Thin Philosophy

Like the best spacecraft, ThrottleMachines follows the principle of **ultra-thin design**:

- **No bloat** - Every component serves a critical function
- **Rust reactor core** - `no_std`, allocation-free, no clock of its own
- **Exact time** - Integer nanoseconds end to end; no float drift at the boundaries
- **Modular systems** - Swap components like ship modules

---

## ⚡ Warp Factor Features

- **🚀 Multiple Algorithms** - GCRA, Token Bucket, Fixed Window
- **💫 Distributed Ready** - Redis backend for fleet coordination
- **🔄 Async Support** - Fiber-safe operations for quantum communications
- **🏃 Hedged Requests** - Multi-path navigation for reduced latency
- **🎯 Nanosecond Precision** - Navigate the cosmos with temporal accuracy
- **🔌 Pluggable Storage** - Memory crystals or Redis quantum storage
- **🌍 Rails Integration** - Seamless planetary docking procedures
- **📡 Rack Middleware** - Universal translator for all spacecraft
- **🔍 Full Instrumentation** - Real-time telemetry via ActiveSupport::Notifications
- **⚡ Thread-Safe** - Safe for multi-threaded spacecraft operations
- **🎭 Multiple Usage Patterns** - Check-first, exception-based, or block form

---

## 🌌 Why ThrottleMachines?

In the vast expanse of cyberspace, your systems face:
- **Asteroid fields** of concurrent requests
- **Black holes** of resource exhaustion
- **Alien attacks** from malicious actors
- **Temporal anomalies** in distributed systems

ThrottleMachines is your navigation system through these dangers, ensuring safe passage for every request in your fleet.

---

## 📜 Captain's Log

See our [Mission Archives](CHANGELOG.md) for the full history of our voyages.

---

## 🤝 Join the Crew

1. Signal your intent (`fork` the repository)
2. Create your feature branch (`git checkout -b feature/quantum-throttling`)
3. Document your modifications (`git commit -am 'Add quantum entanglement support'`)
4. Transmit to mothership (`git push origin feature/quantum-throttling`)
5. Request docking clearance (`Pull Request`)

---

## 📡 Distress Signals

Found a breach in the hull? Encountered an unknown anomaly?
- **Emergency beacon**: [GitHub Issues](https://github.com/seuros/throttle_machines/issues)
- **Mission reports**: [Discussions](https://github.com/seuros/throttle_machines/discussions)

---

## 📡 Credits

**AMS Turner**, NCC-1986, *Turner*-class escort.

Named for Jonathan Turner's *New Directions in Communications* (1986), which
proposed the leaky bucket: let traffic drain at a fixed rate with a bounded
allowance for bursts. GCRA, the algorithm this gem's middleware and controller
helpers default to, is that leaky bucket kept as one theoretical arrival time.

---

## 🎖️ Mission Credentials

MIT License - See [LICENSE](LICENSE) for full transmission.

---

## A Message from the Temporal Defense Corps

*The Quantum Navigation Computer flickers to life:*

"Space is vast. Time is relative. And your API is getting hammered by a bot farm in Eastern Europe.

Welcome to the temporal wars, where milliseconds matter and rate limits are the thin line between order and chaos. You think you're just limiting requests? No, pilot. You're manipulating the very fabric of spacetime to ensure fair resource distribution across the quantum multiverse of your distributed system.

Every request has a trajectory. Every limit has a purpose. Every algorithm is a different spacecraft designed for a specific mission through the hostile void.

The universe doesn't care about your startup's runway or your clever blog post about 'Building a Rate Limiter in 5 Minutes with Redis.' It cares about one immutable law:

**Can your system maintain temporal stability when the thundering herd arrives?**

If not, welcome aboard. We have algorithms."

*— Quantum Navigation Computer, Log Entry ∞*

---

## The Fleet Admiral's Warning

So you built a microservice architecture because a YouTube video told you it was 'web scale'?

Now you're drowning in a sea of uncontrolled requests, cascade failures, and that one service that keeps calling your API 10,000 times per second because someone forgot to implement exponential backoff.

This is your life raft. Don't let go.

---

**"In space, nobody can hear your servers scream. But with ThrottleMachines, they won't need to."**

*— Fleet Admiral J'Rao, Survivor of the Great DDoS Wars of 2019*
