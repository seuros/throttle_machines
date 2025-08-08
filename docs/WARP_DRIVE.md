# ⚡ Warp Drive Configuration

> **Storage Backends & Performance** - Choosing between memory crystals and quantum Redis storage

Your rate limiters need somewhere to store their state. Like choosing between impulse engines and warp drive, each storage backend offers different capabilities for different missions.

---

## 🌌 Storage Systems Overview

| Storage Type | Speed | Persistence | Distributed | Use Case |
|--------------|-------|-------------|-------------|----------|
| **Memory Crystals** | Warp 10 | No | No | Single ship operations |
| **Redis Quantum Core** | Warp 8 | Yes | Yes | Fleet coordination |

---

## 💎 Memory Crystals (Default)

### The Analogy
Memory crystals are like your ship's internal computer - blazing fast but isolated. When the ship powers down (app restarts), all data vanishes into the void.

### Configuration
```ruby
# Default - no configuration needed!
ThrottleMachines.configure do |config|
  # Memory storage is automatic
end

# Each limiter gets its own crystal
limiter = ThrottleMachines.limiter("phaser_array", limit: 10, period: 60)
```

### Characteristics
- **Speed**: Nanosecond access (Warp 10!)
- **Isolation**: Each process has its own storage
- **Volatility**: Data lost on restart
- **Simplicity**: Zero configuration

### Best For
- Development environments
- Single-server deployments
- Stateless applications
- Testing and prototypes

---

## 🔴 Redis Quantum Core

### The Analogy
Redis is like a space station's central computer - all ships in your fleet can share the same data. Even if individual ships go offline, the station remembers everything.

### Basic Configuration
```ruby
require 'redis'
require 'throttle_machines'

# Simple Redis connection
ThrottleMachines.configure do |config|
  config.storage = ThrottleMachines::Storage::Redis.new(
    redis: Redis.new(url: "redis://localhost:6379/0")
  )
end
```

### Fleet-Ready Configuration
```ruby
require 'redis'

# Redis with connection pooling (built-in with ActiveSupport)
redis = Redis.new(
  url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
  timeout: 1,
  reconnect_attempts: 3,
  reconnect_delay: 0.2
)

ThrottleMachines.configure do |config|
  config.storage = ThrottleMachines::Storage::Redis.new(redis: redis)
end
```

### Mission-Critical Configuration
```ruby
# Production-grade setup with failover
class FleetCommand
  def self.configure!
    # Primary Redis cluster
    primary_pool = ConnectionPool.new(size: 20, timeout: 5) do
      Redis.new(
        url: ENV['REDIS_PRIMARY_URL'],
        password: ENV['REDIS_PASSWORD'],
        ssl: true,
        timeout: 1,
        connect_timeout: 2,
        reconnect_attempts: 3,
        reconnect_delay: 0.5,
        reconnect_delay_max: 2.0
      )
    end
    
    ThrottleMachines.configure do |config|
      config.storage = ThrottleMachines::Storage::Redis.new(
        pool: primary_pool,
        prefix: "throttle:#{ENV['ENVIRONMENT']}:",  # Namespace by environment
        expires_in: 7200  # Auto-cleanup after 2 hours
      )
      
      # Configure default algorithm for the fleet
      config.default_algorithm = :gcra
    end
  end
end
```

---

## 🛸 Storage Patterns

### Pattern 1: Multi-Region Fleet Coordination
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
  
  def create_limiter(name, **options)
    ThrottleMachines.limiter(
      "#{@region}:#{name}",
      storage: @storage,
      **options
    )
  end
end

# Usage
us_throttle = MultiRegionThrottle.new("us-east")
eu_throttle = MultiRegionThrottle.new("eu-west")

us_limiter = us_throttle.create_limiter("api", limit: 1000, period: 60)
eu_limiter = eu_throttle.create_limiter("api", limit: 1000, period: 60)
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
  
  def create_limiter(name, tier: :standard, **options)
    storage = case tier
    when :local
      @memory_storage  # Ultra-fast, single-server
    when :distributed
      @redis_storage   # Coordinated across fleet
    else
      # Hybrid approach could be implemented here
      @redis_storage
    end
    
    ThrottleMachines.limiter(name, storage: storage, **options)
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
  
  def create_limiter(name, **options)
    ThrottleMachines.limiter(name, **options).tap do |limiter|
      # Add custom error handling
      limiter.define_singleton_method(:allowed?) do
        begin
          super()
        rescue Redis::ConnectionError => e
          # Log the error
          Rails.logger.error "Redis primary failed: #{e.message}"
          
          # Could implement fallback logic here
          # For now, fail open (allow the request)
          true
        end
      end
    end
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
   # Auto-expire keys to prevent memory bloat
   ThrottleMachines::Storage::Redis.new(
     pool: redis_pool,
     expires_in: 3600  # 1 hour - should be > your longest period
   )
   ```

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
# For memory storage, implement periodic cleanup
class MemoryMaintenanceCrew
  def self.cleanup!
    return unless using_memory_storage?
    
    # Clear expired entries periodically
    Thread.new do
      loop do
        sleep 300  # Every 5 minutes
        ThrottleMachines.storage.cleanup_expired!
      end
    end
  end
end
```

---

## 📊 Monitoring Your Warp Core

### Redis Monitoring
```ruby
class ThrottleMonitor
  def self.stats
    storage = ThrottleMachines.configuration.storage
    return {} unless storage.is_a?(ThrottleMachines::Storage::Redis)
    
    storage.with_redis do |redis|
      {
        total_keys: redis.dbsize,
        throttle_keys: redis.keys("throttle:*").count,
        memory_usage: redis.info("memory")["used_memory_human"],
        connected_clients: redis.info("clients")["connected_clients"]
      }
    end
  end
  
  def self.health_check
    ThrottleMachines.limiter("health_check", limit: 1, period: 1).allowed?
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
# Implement circuit breaker for Redis failures
class StorageCircuitBreaker
  def initialize
    @failure_count = 0
    @circuit_open = false
    @last_failure = nil
  end
  
  def with_circuit
    return yield if @circuit_open && Time.now - @last_failure < 30
    
    begin
      result = yield
      @failure_count = 0  # Reset on success
      @circuit_open = false
      result
    rescue Redis::ConnectionError => e
      @failure_count += 1
      @last_failure = Time.now
      
      if @failure_count >= 3
        @circuit_open = true
        Rails.logger.error "Storage circuit opened after #{@failure_count} failures"
      end
      
      # Fail open - allow requests when storage is down
      true
    end
  end
end
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
- Running multiple servers
- Need persistent rate limits
- Building distributed systems
- Sharing limits across services
- Production deployments

---

## 📚 Next Missions

- **[🛡️ Shield Protocols](SHIELD_PROTOCOLS.md)** - Circuit breakers for protection
- **[🌍 Planetary Integration](PLANETARY_INTEGRATION.md)** - Rails and Rack setup
- **[📡 Telemetry](TELEMETRY.md)** - Monitoring your fleet

---

**"A ship without proper storage is like a captain without memory - doomed to repeat past mistakes."**

*— Engineering Manual, Warp Core Maintenance*