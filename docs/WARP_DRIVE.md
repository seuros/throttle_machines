# ⚡ Warp Drive Configuration

> **Storage Backends & Performance** - Choosing between memory crystals and quantum Redis storage

Your rate limiters need somewhere to store their state. Like choosing between impulse engines and warp drive, each storage backend offers different capabilities for different missions.

---

## 🌌 Storage Systems Overview

| Storage Type | Speed | Persistence | Distributed | Use Case |
|--------------|-------|-------------|-------------|----------|
| **Memory Crystals** | Warp 10 | No | No | Single process operations |
| **Redis Quantum Core** | Warp 8 | Yes | One host | Every process aboard one ship |
| **Rails Cache Relay** | Warp 6 | Yes | Yes | Fleet coordination (`:fixed_window` only) |

Every span below is Integer nanoseconds: periods, TTLs, cleanup intervals. No Floats, no `.seconds`.

---

## 💎 Memory Crystals (Default)

### The Analogy
Memory crystals are like your ship's internal computer - blazing fast but isolated. When the ship powers down (app restarts), all data vanishes into the void.

### Configuration
```ruby
NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000

# Default - no configuration needed!
ThrottleMachines.configure do |config|
  # Memory storage is automatic (config.default_storage = :memory)
end

# Every limiter in the process shares the one crystal: ThrottleMachines.storage
limiter = ThrottleMachines.limiter("phaser_array", limit: 10, period: 60 * NS)
```

### Characteristics
- **Speed**: Nanosecond access (Warp 10!)
- **Isolation**: Each process has its own storage
- **Volatility**: Data lost on restart
- **Simplicity**: Zero configuration
- **Bounded**: At most 65,536 entries (`max_keys:`); new identities are refused with `:full` when the crystal is saturated, active ones are never evicted

### Best For
- Development environments
- Single-server deployments
- Stateless applications
- Testing and prototypes

---

## 🔴 Redis Quantum Core

### The Analogy
Redis is like a space station's central computer - every process docked to it shares the same data. Even if individual processes go offline, the station remembers everything.

The station keeps the only clock that counts: every Lua script reads Redis `TIME`, so processes docked from any number of hosts share one store and one clock, and no ship's chronometer ever reaches the limits. If the station's own clock jumps (an NTP step, a failover to a replica on another host), the limits see the jump.

Upgrading from a release whose scripts took the caller's clock: GCRA state is now a hash, and stored instants count from a Redis `TIME` second, so clear the old throttle keys (`ThrottleMachines.storage.clear`) once before the new scripts run.

### Basic Configuration
```ruby
require 'redis'
require 'throttle_machines'

# Simple Redis connection
ThrottleMachines.storage = ThrottleMachines::Storage::Redis.new(
  redis: Redis.new(url: "redis://localhost:6379/0")
)
```

### Fleet-Ready Configuration
```ruby
require 'redis'

# A single hardened client (redis-rb's own timeouts are in seconds - its API, not ours)
redis = Redis.new(
  url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
  timeout: 1,
  reconnect_attempts: 3
)

ThrottleMachines.storage = ThrottleMachines::Storage::Redis.new(redis: redis)
```

### Mission-Critical Configuration
```ruby
# Production-grade setup with failover
class FleetCommand
  def self.configure!
    # Primary Redis (connection_pool and redis-rb timeouts are seconds - their API)
    primary_pool = ConnectionPool.new(size: 20, timeout: 5) do
      Redis.new(
        url: ENV['REDIS_PRIMARY_URL'],
        password: ENV['REDIS_PASSWORD'],
        ssl: true,
        timeout: 1,
        connect_timeout: 2,
        reconnect_attempts: 3
      )
    end

    # Keys expire on their own: a fixed window lives one window,
    # GCRA and token bucket state lives twice the limiter's period.
    ThrottleMachines.storage = ThrottleMachines::Storage::Redis.new(
      pool: primary_pool,
      prefix: "throttle:#{ENV['ENVIRONMENT']}:"  # Namespace by environment
    )

    ThrottleMachines.configure do |config|
      # Configure default algorithm for the fleet
      config.default_algorithm = :gcra
    end
  end
end
```

---

## 🛰️ Rails Cache Relay

### The Analogy
When the fleet is scattered across star systems (hosts), nobody shares a monotonic clock. The relay counts fixed windows in any `ActiveSupport::Cache` store, aligned to the wall-clock epoch, so every ship counts the same window.

```ruby
ThrottleMachines.storage = ThrottleMachines::Storage::Cache.new(cache_store: Rails.cache)
# or, inside Rails: config.default_storage = :cache

limiter = ThrottleMachines.limiter("fleet_api", limit: 1000, period: 60 * NS, algorithm: :fixed_window)
```

It supports `:fixed_window` only; building a GCRA or token bucket limiter on it raises `RangeError`. When the store fails to count, requests are admitted; pass `fail_closed: true` to throttle them instead.

---

## 🛸 Storage Patterns

### Pattern 1: Multi-Region Fleet Coordination
Each region keeps its own station, and every host in a region shares its Redis and its clock.

`ThrottleMachines.limiter` always uses `ThrottleMachines.storage`; to pick a store per limiter, build `ThrottleMachines::Limiter` directly.

```ruby
class MultiRegionThrottle
  def initialize(region)
    @region = region
    @redis_pool = ConnectionPool.new(size: 5) do
      Redis.new(url: ENV["REDIS_#{region.upcase}_URL"])
    end

    @storage = ThrottleMachines::Storage::Redis.new(
      pool: @redis_pool,
      prefix: "region:#{region}:"
    )
  end

  def create_limiter(name, limit:, period:, algorithm: :gcra)
    ThrottleMachines::Limiter.new(
      "#{@region}:#{name}",
      limit: limit,
      period: period,
      algorithm: algorithm,
      storage: @storage
    )
  end
end

# Usage
us_throttle = MultiRegionThrottle.new("us-east")
eu_throttle = MultiRegionThrottle.new("eu-west")

us_limiter = us_throttle.create_limiter("api", limit: 1000, period: 60 * NS)
eu_limiter = eu_throttle.create_limiter("api", limit: 1000, period: 60 * NS)
```

### Pattern 2: Tiered Storage Strategy
```ruby
class TieredThrottleSystem
  def initialize
    # Fast local cache for frequent checks
    @memory_storage = ThrottleMachines::Storage::Memory.new

    # Distributed storage for coordination
    @redis_storage = ThrottleMachines::Storage::Redis.new(
      pool: ConnectionPool.new { Redis.new }
    )
  end

  def create_limiter(name, limit:, period:, tier: :standard, algorithm: :gcra)
    storage = case tier
    when :local
      @memory_storage  # Ultra-fast, single process
    when :distributed
      @redis_storage   # Coordinated across every process on the host
    else
      # Hybrid approach could be implemented here
      @redis_storage
    end

    ThrottleMachines::Limiter.new(name, limit: limit, period: period, algorithm: algorithm, storage: storage)
  end
end
```

### Pattern 3: Failover Configuration
```ruby
class ResilientThrottle
  def initialize
    @primary_pool = ConnectionPool.new(size: 10) do
      Redis.new(url: ENV['REDIS_PRIMARY_URL'])
    end

    @fallback_pool = ConnectionPool.new(size: 10) do
      Redis.new(url: ENV['REDIS_SECONDARY_URL'])
    end
  end

  # Limiters are frozen, so wrap the check instead of patching the limiter
  def allow?(limiter)
    limiter.allow?
  rescue Redis::BaseConnectionError => e
    # Log the error
    Rails.logger.error "Redis primary failed: #{e.message}"

    # Could implement fallback logic here
    # For now, fail open (allow the request)
    true
  end
end
```

---

## 🔧 Performance Tuning

### Redis Optimization Tips

1. **Connection Pool Sizing**
   ```ruby
   # Formula: pool_size = number_of_threads + headroom
   pool_size = Thread.list.select { |t| t.status == "run" }.count + 5

   ConnectionPool.new(size: pool_size, timeout: 5) do
     Redis.new
   end
   ```

2. **Key Expiration Strategy**
   ```ruby
   # Keys auto-expire from the limiter's own period - nothing to configure:
   #   :fixed_window           -> one window
   #   :gcra / :token_bucket   -> 2 * period
   ThrottleMachines.limiter("scanner", limit: 100, period: 3600 * NS)  # state gone within 2 hours
   ```
   There is no application-level key cap on Redis: set `maxmemory` on the server, and remember that evicting active keys resets their limits.

3. **Namespace Organization**
   ```ruby
   # Organize keys by service and environment
   ThrottleMachines::Storage::Redis.new(
     pool: redis_pool,
     prefix: "throttle:#{Rails.env}:#{service_name}:"
   )
   ```

### Memory Storage Optimization

```ruby
# The memory crystal ships with its own maintenance crew: a background
# sweeper reclaims expired entries every cleanup_interval (default 60 s).
ThrottleMachines.storage = ThrottleMachines::Storage::Memory.new(
  max_keys: 10_000,                # bound the entry count
  cleanup_interval: 5 * 60 * NS    # sweep every 5 minutes
)

# No background thread at all (expired entries are still reclaimed on
# demand when the crystal saturates, at most once per second)
ThrottleMachines.storage = ThrottleMachines::Storage::Memory.new(auto_cleanup: false)
```

---

## 📊 Monitoring Your Warp Core

### Redis Monitoring
```ruby
class ThrottleMonitor
  # Pass the same client (or pool checkout) you handed to Storage::Redis
  def self.stats(redis)
    return {} unless ThrottleMachines.storage.is_a?(ThrottleMachines::Storage::Redis)

    {
      total_keys: redis.dbsize,
      throttle_keys: redis.scan_each(match: "throttle:*").count,  # SCAN, never KEYS
      memory_usage: redis.info("memory")["used_memory_human"],
      connected_clients: redis.info("clients")["connected_clients"]
    }
  end

  def self.health_check
    return { status: "unhealthy", storage: "redis" } unless ThrottleMachines.storage.healthy?

    ThrottleMachines.limiter("health_check", limit: 1, period: 1 * NS).allow?
    { status: "healthy", storage: "redis" }
  rescue => e
    { status: "unhealthy", error: e.message }
  end
end
```

---

## 🚨 Emergency Procedures

### Redis Connection Lost
```ruby
# Don't hand-roll it: put a BreakerMachines circuit in front of Redis.
# Opens after 3 connection failures within 30 s, stays open 30 s,
# then one successful probe closes it.
class StorageCircuitBreaker
  def initialize
    @circuit = ThrottleMachines::Breakers.dynamic(
      "storage:redis", self, 3, 30 * NS, 30 * NS,
      exceptions: [Redis::BaseConnectionError],
      fallback: true,  # Fail open - allow requests when storage is down
      on_open: -> { Rails.logger.error "Storage circuit opened" }
    )
  end

  def with_circuit(&)
    @circuit.call(&)
  end
end

shield = StorageCircuitBreaker.new
shield.with_circuit { limiter.allow? }  # => true while Redis is down
```

---

## 🎯 Storage Selection Guide

### Choose Memory Storage When:
- Running a single server
- Building a prototype
- Testing or development
- Stateless applications
- Maximum performance needed

### Choose Redis Storage When:
- Running multiple processes on one host
- Need persistent rate limits
- Need GCRA or token bucket shared across processes
- Sharing limits across services on the same host
- Production deployments

### Choose Rails Cache Storage When:
- Running multiple servers
- Building distributed systems
- A fixed window is precise enough

---

## 📚 Next Missions

- **[🛡️ Shield Protocols](SHIELD_PROTOCOLS.md)** - Circuit breakers for protection
- **[🌍 Planetary Integration](PLANETARY_INTEGRATION.md)** - Rails and Rack setup
- **[📡 Telemetry](TELEMETRY.md)** - Monitoring your fleet

---

**"A ship without proper storage is like a captain without memory - doomed to repeat past mistakes."**

*— Engineering Manual, Warp Core Maintenance*
