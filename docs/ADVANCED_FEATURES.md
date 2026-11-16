# 🚀 Advanced Features

> **Next-Generation Capabilities** - Powered by BreakerMachines' circuits

ThrottleMachines ships with BreakerMachines aboard, bringing enterprise-grade capabilities to your rate limiting infrastructure. The advanced circuit types below are BreakerMachines' own; `ThrottleMachines::Breakers.policy(failures, window, cooldown)` shapes the policy they run. Every span is **Integer nanoseconds**.

```ruby
NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000
MS = 1_000_000
```

---

## 🌊 Cascading Circuit Breakers

### The Shield Cascade Protocol

When your main shield generator fails, you don't want every dependent system trying to access it. Cascading breakers automatically protect dependent services when a primary service fails.

```ruby
# Dependents are ordinary circuits, found by name through the registry
%w[user_service order_service inventory_service].each do |name|
  BreakerMachines::Circuit.new(name, ThrottleMachines::Breakers.policy(5, 60 * NS, 60 * NS))
end

# If the database fails, automatically protect all services that depend on it
database_shield = BreakerMachines::CascadingCircuit.new("main_database",
  ThrottleMachines::Breakers.policy(5, 60 * NS, 300 * NS), # 5 minute recovery
  cascades_to: ["user_service", "order_service", "inventory_service"],
  # Monitor cascade events: called with the names of the circuits it tripped
  on_cascade: ->(tripped) { AlertSystem.notify("Shield cascade activated: main_database -> #{tripped.join(', ')}") }
)

# Use it like a regular breaker
database_shield.call do
  Database.query("SELECT * FROM users")
end
```

### Cascade Status Monitoring

```ruby
# Each dependent's state (:not_found when it is not registered)
database_shield.dependent_status
# => { "user_service" => :open, "order_service" => :open, "inventory_service" => :open }

database_shield.dependents_compromised? # => true
database_shield.cascade_info            # dependent_circuits, emergency_protocol,
                                        # cascade_triggered_at (Integer ns), dependent_status
database_shield.cascade_failure!        # trip the dependents by hand

# Reset only the primary...
database_shield.reset
# ...then bring the dependents back too
database_shield.dependent_circuits.each { |name| BreakerMachines.registry.reset(name) }
```

---

## 🔄 Async Support

### Quantum Entanglement Communications

For modern Ruby applications using fibers and async/await patterns, ThrottleMachines provides optional fiber-safe async support. Add the `async` gem only when you enable fiber-safe mode.

```ruby
ThrottleMachines.configure do |config|
  config.fiber_safe = true # loads the async gem
  config.default_algorithm = :gcra
end

# Every limiter is async-aware
quantum_limiter = ThrottleMachines.limiter("quantum_comm",
  limit: 1000,
  period: 60 * NS,
  algorithm: :gcra
)

# In async context
Async do
  if quantum_limiter.allowed_async?
    # Non-consuming availability check
    response = async_api_call
  end

  # Or consume capacity with cooperative retry, waiting at most 5 s
  result = quantum_limiter.throttle_async(max_wait: 5 * NS) do
    perform_operation
  end
end
```

### Async Circuit Breakers

```ruby
# A BreakerMachines::AsyncCircuit, fiber-safe by default
async_shield = ThrottleMachines::AsyncBreaker.new("async_service",
  ThrottleMachines::Breakers.policy(3, 60 * NS, 60 * NS)
)

# Run async with automatic state management
Async do
  task = async_shield.call_async do
    fetch_remote_data
  end

  result = task.wait

  # Fire a state transition asynchronously (:force_open, :force_close or :reset)
  async_shield.fire_async(:reset)

  # Health report as a task: name, state, open, stats, can_recover
  health = async_shield.health_check_async.wait
end
```

---

## 🎛️ Circuit Groups

### Fleet Coordination System

Manage related circuits as a unified fleet with dependencies and shared configuration. A group holds circuits only; pair it with limiters for rate limits.

```ruby
policy = ThrottleMachines::Breakers.method(:policy)

payment_fleet = BreakerMachines::CircuitGroup.new("payment_system")

# Main payment gateway
payment_fleet.circuit(:gateway, policy.(5, 60 * NS, 300 * NS))

# Operations that depend on it
payment_fleet.circuit(:charge, policy.(5, 60 * NS, 60 * NS), depends_on: :gateway)
payment_fleet.circuit(:refund, policy.(5, 60 * NS, 60 * NS), depends_on: :gateway)
payment_fleet.circuit(:void, policy.(5, 60 * NS, 60 * NS), depends_on: [:gateway, :charge])

# Webhook system depends on gateway
payment_fleet.circuit(:webhooks, policy.(3, 60 * NS, 60 * NS), depends_on: :gateway)

# Rate limits live beside the group
charge_limiter = ThrottleMachines.limiter("payment_system.charge", limit: 100, period: 60 * NS)

# Check operational status
payment_fleet.all_healthy?  # false unless every circuit is closed
payment_fleet.any_open?

# Execute with dependency checking. Throttle outside the circuit:
# a ThrottledError raised inside it would count as a failure.
begin
  charge_limiter.throttle! do
    payment_fleet[:charge].call do
      process_payment(amount: 100)
    end
  end
rescue BreakerMachines::CircuitDependencyError
  # Gateway is down, charge operation blocked
end

# Emergency protocols
payment_fleet.trip_all!   # Force every circuit open
payment_fleet.reset_all!  # Reset entire fleet

# Get fleet status
status = payment_fleet.status # => { gateway: :closed, charge: :closed, ... }
```

---

## 🏃 Hedged Requests

### Multi-Path Navigation

Send scout ships on multiple routes and use the fastest response. Perfect for reducing latency with redundant backends.

```ruby
# Configure hedged requests
navigator = ThrottleMachines::HedgedRequest.new(
  delay: 50 * MS,   # 50ms between attempts
  max_attempts: 3,  # Try up to 3 backends
  timeout: 1 * NS   # Overall timeout
)

# Race multiple backends
result = navigator.run do |attempt|
  case attempt
  when 0
    primary_backend.get(key)    # Fast but sometimes flaky
  when 1
    secondary_backend.get(key)  # Slower but reliable
  when 2
    cache_backend.get(key)      # Fallback to cache
  end
end

# The first successful response wins!
navigator.shutdown # or use ThrottleMachines.hedged_request(...) { }, which shuts down for you
```

### Hedged Circuit Breakers

```ruby
# Combine hedging with circuit breakers
backend_policy = ThrottleMachines::Breakers.policy(3, 60 * NS, 60 * NS)
breaker1 = BreakerMachines::Circuit.new("backend1", backend_policy)
breaker2 = BreakerMachines::Circuit.new("backend2", backend_policy)
breaker3 = BreakerMachines::Circuit.new("backend3", backend_policy)

hedged = ThrottleMachines::HedgedBreaker.new([breaker1, breaker2, breaker3], delay: 50 * MS)

result = hedged.run do
  fetch_critical_data
end
```

---

## 🎯 Integration Examples

### Multi-Region Deployment with Cascading Protection

```ruby
# Regional deployment with cascade protection
regions = %w[us-east us-west eu-central].map do |region|
  BreakerMachines::CascadingCircuit.new("api_#{region}",
    ThrottleMachines::Breakers.policy(10, 60 * NS, 300 * NS),
    cascades_to: ["cache_#{region}", "db_#{region}"]
  )
end

# If us-east fails, its cache and db circuits are automatically forced open
```

### Async Microservice Mesh

```ruby
policy = ThrottleMachines::Breakers.method(:policy)

# Runtime keywords given to the group reach every circuit it builds
service_mesh = BreakerMachines::CircuitGroup.new("microservices", fiber_safe: true)

# Core services
service_mesh.circuit(:auth, policy.(5, 60 * NS, 60 * NS))
service_mesh.circuit(:user_data, policy.(5, 60 * NS, 60 * NS), depends_on: :auth)
service_mesh.circuit(:graphql, policy.(5, 60 * NS, 60 * NS), depends_on: [:auth, :user_data])

# Async rate limiter at the gate
api_gateway = ThrottleMachines.limiter("api_gateway", limit: 10_000, period: 60 * NS, algorithm: :gcra)

# Async request handling
Async do
  api_gateway.throttle_async(max_wait: 100 * MS) do
    service_mesh[:graphql].call do
      process_graphql_query
    end
  end
end
```

### Intelligent Backend Selection

```ruby
class SmartBackendSelector
  def initialize
    @primary = ThrottleMachines::AsyncBreaker.new("primary_api",
      ThrottleMachines::Breakers.policy(3, 60 * NS, 60 * NS))
    @secondary = ThrottleMachines::AsyncBreaker.new("secondary_api",
      ThrottleMachines::Breakers.policy(5, 60 * NS, 120 * NS))
    @hedged = ThrottleMachines::HedgedRequest.new(delay: 100 * MS, max_attempts: 2)
  end

  def fetch_data(key)
    # Try primary first
    return @primary.call { primary_api.get(key) } unless @primary.open?

    # If primary is down, use hedged request on secondaries
    @hedged.run do |attempt|
      case attempt
      when 0 then @secondary.call { secondary_api.get(key) }
      when 1 then fetch_from_cache(key)
      end
    end
  rescue ThrottleMachines::CircuitOpenError
    # All circuits open, return degraded response
    { status: "degraded", data: nil }
  end
end
```

---

## 🔧 Configuration Best Practices

### Production-Ready Setup

```ruby
# config/initializers/throttle_machines_advanced.rb
NS = ThrottleMachines::NS_PER_SECOND
MS = 1_000_000

# Configure async support
if defined?(Async)
  ThrottleMachines.configure do |config|
    config.default_algorithm = :gcra  # Best for async
    config.fiber_safe = true
  end
end

# Global cascade protection for critical services
CRITICAL_SERVICES = BreakerMachines::CascadingCircuit.new("critical_infra",
  ThrottleMachines::Breakers.policy(10, 60 * NS, 600 * NS), # 10 minutes
  cascades_to: %w[api cache database search messaging]
)

# Service mesh configuration
policy = ThrottleMachines::Breakers.method(:policy)
SERVICE_MESH = BreakerMachines::CircuitGroup.new("production")

# Database layer
SERVICE_MESH.circuit(:primary_db, policy.(5, 60 * NS, 300 * NS))
SERVICE_MESH.circuit(:read_replica, policy.(10, 60 * NS, 60 * NS))

# Caching layer
SERVICE_MESH.circuit(:redis_cache, policy.(3, 60 * NS, 30 * NS))
SERVICE_MESH.circuit(:memcached, policy.(5, 60 * NS, 30 * NS))

# API layer with dependencies
SERVICE_MESH.circuit(:public_api, policy.(10, 60 * NS, 60 * NS),
  depends_on: [:primary_db, :redis_cache])
SERVICE_MESH.circuit(:admin_api, policy.(10, 60 * NS, 60 * NS),
  depends_on: [:primary_db])

# ...and their rate limits
PUBLIC_API_LIMIT = ThrottleMachines.limiter("public_api", limit: 10_000, period: 60 * NS)
ADMIN_API_LIMIT = ThrottleMachines.limiter("admin_api", limit: 1000, period: 60 * NS)

# Hedged request configuration for external APIs
EXTERNAL_API_HEDGED = ThrottleMachines::HedgedRequest.new(
  delay: 100 * MS,  # 100ms between attempts
  max_attempts: 3,  # Try 3 different endpoints
  timeout: 2 * NS   # 2 second overall timeout
)
```

---

## 📊 Monitoring Advanced Features

```ruby
# Custom monitoring for advanced features
class AdvancedThrottleMonitor
  def self.collect_metrics
    {
      cascade_status: collect_cascade_metrics,
      circuit_groups: collect_group_metrics,
      fleet: BreakerMachines.registry.stats_summary # total, by_state, by_name
    }
  end

  private

  def self.collect_cascade_metrics
    # Monitor cascade activations
    CRITICAL_SERVICES.cascade_info.to_h
  end

  def self.collect_group_metrics
    # Monitor service mesh health
    SERVICE_MESH.status
  end
end
```

---

## 🚀 Performance Considerations

1. **Cascading Breakers**: Minimal overhead, but monitor cascade chains to prevent over-protection
2. **Async Support**: Requires the `async` gem; waits yield to the scheduler instead of blocking the thread
3. **Circuit Groups**: Dependency checking is O(n) - keep dependency chains shallow
4. **Hedged Requests**: Increases backend load - monitor and adjust delays

---

**"With great power comes great responsibility. Use these advanced features wisely."**

*— Starfleet Engineering Manual, Advanced Systems*
