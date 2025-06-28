# 🚀 Advanced Features

> **Next-Generation Capabilities** - Inspired by BreakerMachines' innovations

ThrottleMachines now includes advanced features for complex distributed systems, bringing enterprise-grade capabilities to your rate limiting infrastructure.

---

## 🌊 Cascading Circuit Breakers

### The Shield Cascade Protocol

When your main shield generator fails, you don't want every dependent system trying to access it. Cascading breakers automatically protect dependent services when a primary service fails.

```ruby
# If the database fails, automatically protect all services that depend on it
database_shield = ThrottleMachines::CascadingBreaker.new("main_database",
  failure_threshold: 5,
  timeout: 300,  # 5 minute recovery
  cascades_to: ["user_service", "order_service", "inventory_service"]
)

# Monitor cascade events
database_shield.on_cascade do |primary, cascaded|
  AlertSystem.notify("Shield cascade activated: #{primary} -> #{cascaded}")
end

# Use it like a regular breaker
database_shield.call do
  Database.query("SELECT * FROM users")
end
```

### Cascade Status Monitoring

```ruby
# Get complete cascade chain status
status = database_shield.cascade_status
# => {
#   primary: { name: "main_database", state: :open, failures: 5 },
#   cascaded: [
#     { name: "user_service", state: :open, failures: 0 },
#     { name: "order_service", state: :open, failures: 0 },
#     { name: "inventory_service", state: :open, failures: 0 }
#   ]
# }

# Reset with cascade control
database_shield.reset!(cascade: true)  # Reset all
database_shield.reset!(cascade: false) # Reset only primary
```

---

## 🔄 Async Support

### Quantum Entanglement Communications

For modern Ruby applications using fibers and async/await patterns, ThrottleMachines provides fiber-safe async support.

```ruby
# Async-aware rate limiter
quantum_limiter = ThrottleMachines::AsyncLimiter.new("quantum_comm",
  limit: 1000,
  period: 60,
  algorithm: :gcra
)

# In async context
Async do
  if quantum_limiter.allowed_async?
    # Non-blocking operation
    response = async_api_call
  end
  
  # Or with automatic retry
  result = quantum_limiter.throttle_async(max_wait: 5) do
    perform_operation
  end
end
```

### Async Circuit Breakers

```ruby
async_shield = ThrottleMachines::AsyncBreaker.new("async_service",
  failure_threshold: 3,
  timeout: 60
)

# Run async with automatic state management
Async do
  result = async_shield.run_async do
    fetch_remote_data
  end
  
  # Fire and forget
  async_shield.fire_async do
    send_telemetry_data
  end
end
```

---

## 🎛️ Circuit Groups

### Fleet Coordination System

Manage related circuits as a unified fleet with dependencies and shared configuration.

```ruby
payment_fleet = ThrottleMachines::CircuitGroup.new("payment_system") do
  # Main payment gateway
  breaker :gateway, failures: 5, timeout: 300
  
  # Rate limiters with dependencies
  limiter :charge, limit: 100, period: 60, depends_on: :gateway
  limiter :refund, limit: 50, period: 60, depends_on: :gateway
  limiter :void, limit: 20, period: 60, depends_on: [:gateway, :charge]
  
  # Webhook system depends on gateway
  breaker :webhooks, failures: 3, timeout: 60, depends_on: :gateway
end

# Check operational status
payment_fleet.operational?  # false if any breaker is open

# Execute with dependency checking
begin
  payment_fleet.execute(:charge) do
    process_payment(amount: 100)
  end
rescue ThrottleMachines::DependencyError => e
  # Gateway is down, charge operation blocked
end

# Emergency protocols
payment_fleet.emergency_shutdown!  # Trip all breakers
payment_fleet.reset_all!          # Reset entire fleet

# Get fleet status
status = payment_fleet.status
```

---

## 🏃 Hedged Requests

### Multi-Path Navigation

Send scout ships on multiple routes and use the fastest response. Perfect for reducing latency with redundant backends.

```ruby
# Configure hedged requests
navigator = ThrottleMachines::HedgedRequest.new(
  delay: 0.05,      # 50ms between attempts
  max_attempts: 3,  # Try up to 3 backends
  timeout: 1.0      # Overall timeout
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
```

### Hedged Circuit Breakers

```ruby
# Combine hedging with circuit breakers
breaker1 = ThrottleMachines::Breaker.new("backend1", failure_threshold: 3, timeout: 60)
breaker2 = ThrottleMachines::Breaker.new("backend2", failure_threshold: 3, timeout: 60)
breaker3 = ThrottleMachines::Breaker.new("backend3", failure_threshold: 3, timeout: 60)

hedged = ThrottleMachines::HedgedBreaker.new([breaker1, breaker2, breaker3])

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
  ThrottleMachines::CascadingBreaker.new("api_#{region}",
    failure_threshold: 10,
    timeout: 300,
    cascades_to: ["cache_#{region}", "db_#{region}"]
  )
end

# If us-east fails, its cache and db are automatically protected
```

### Async Microservice Mesh

```ruby
service_mesh = ThrottleMachines::CircuitGroup.new("microservices") do
  # Core services
  breaker :auth, failures: 5, timeout: 60
  breaker :user_data, failures: 5, timeout: 60, depends_on: :auth
  
  # Async rate limiters
  limiter :api_gateway, limit: 10000, period: 60, algorithm: :gcra
  limiter :graphql, limit: 1000, period: 60, depends_on: [:auth, :user_data]
end

# Async request handling
Async do
  if service_mesh[:api_gateway].allowed_async?
    service_mesh.execute(:graphql) do
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
      failure_threshold: 3, timeout: 60)
    @secondary = ThrottleMachines::AsyncBreaker.new("secondary_api", 
      failure_threshold: 5, timeout: 120)
    @hedged = ThrottleMachines::HedgedRequest.new(delay: 0.1, max_attempts: 2)
  end
  
  def fetch_data(key)
    # Try primary first
    return @primary.call { primary_api.get(key) } if @primary.allow?
    
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

# Configure async support
if defined?(Async)
  ThrottleMachines.configure do |config|
    config.default_algorithm = :gcra  # Best for async
    config.async_enabled = true
  end
end

# Global cascade protection for critical services
CRITICAL_SERVICES = ThrottleMachines::CascadingBreaker.new("critical_infra",
  failure_threshold: 10,
  timeout: 600,  # 10 minutes
  cascades_to: %w[api cache database search messaging]
)

# Service mesh configuration
SERVICE_MESH = ThrottleMachines::CircuitGroup.new("production") do
  # Database layer
  breaker :primary_db, failures: 5, timeout: 300
  breaker :read_replica, failures: 10, timeout: 60
  
  # Caching layer
  breaker :redis_cache, failures: 3, timeout: 30
  breaker :memcached, failures: 5, timeout: 30
  
  # API layer with dependencies
  limiter :public_api, limit: 10000, period: 60, 
    depends_on: [:primary_db, :redis_cache]
  limiter :admin_api, limit: 1000, period: 60,
    depends_on: [:primary_db]
end

# Hedged request configuration for external APIs
EXTERNAL_API_HEDGED = ThrottleMachines::HedgedRequest.new(
  delay: 0.1,      # 100ms between attempts
  max_attempts: 3,  # Try 3 different endpoints
  timeout: 2.0      # 2 second overall timeout
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
      async_performance: collect_async_metrics,
      circuit_groups: collect_group_metrics,
      hedged_success_rate: collect_hedged_metrics
    }
  end
  
  private
  
  def self.collect_cascade_metrics
    # Monitor cascade activations
    CRITICAL_SERVICES.cascade_status
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
2. **Async Support**: Fiber-local storage has slight memory overhead
3. **Circuit Groups**: Dependency checking is O(n) - keep dependency chains shallow
4. **Hedged Requests**: Increases backend load - monitor and adjust delays

---

**"With great power comes great responsibility. Use these advanced features wisely."**

*— Starfleet Engineering Manual, Advanced Systems*