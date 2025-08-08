# 📡 Instrumentation Guide

> **Mission Telemetry** - Monitor your rate limiting and circuit breaking in real-time

ThrottleMachines provides comprehensive instrumentation to help you understand exactly what's happening with your rate limiting and circuit breaking in production.

---

## 🚀 Quick Start

```ruby
# Enable instrumentation (enabled by default)
ThrottleMachines.configure do |config|
  config.instrumentation_enabled = true
end

# Subscribe to all events
ActiveSupport::Notifications.subscribe(/throttle_machines/) do |name, start, finish, id, payload|
  Rails.logger.info "[#{name}] #{payload}"
end
```

---

## 📊 Available Events

### Rate Limiter Events

#### `rate_limit.checked.throttle_machines`
Emitted every time a rate limit is checked.

```ruby
# Payload:
{
  key: "api:user:123",
  limit: 100,
  period: 60,
  algorithm: :gcra,
  allowed: true,
  remaining: 95
}
```

#### `rate_limit.allowed.throttle_machines`
Emitted when a request is allowed through.

```ruby
# Payload:
{
  key: "api:user:123",
  limit: 100,
  period: 60,
  algorithm: :gcra,
  remaining: 94
}
```

#### `rate_limit.throttled.throttle_machines` ⚠️
Emitted when a rate limit is exceeded.

```ruby
# Payload:
{
  key: "api:user:123",
  limit: 100,
  period: 60,
  algorithm: :gcra,
  retry_after: 45.2  # seconds until next allowed request
}
```

### Circuit Breaker Events

#### `circuit_breaker.opened.throttle_machines` 🚨
Emitted when a circuit breaker trips open.

```ruby
# Payload:
{
  key: "payment_gateway",
  failure_threshold: 5,
  timeout: 300,
  failure_count: 5
}
```

#### `circuit_breaker.closed.throttle_machines` ✅
Emitted when a circuit breaker closes (recovers).

```ruby
# Payload:
{
  key: "payment_gateway",
  failure_threshold: 5,
  timeout: 300
}
```

#### `circuit_breaker.half_opened.throttle_machines`
Emitted when a circuit enters half-open state for testing.

```ruby
# Payload:
{
  key: "payment_gateway",
  failure_threshold: 5,
  timeout: 300,
  half_open_requests: 3
}
```

#### `circuit_breaker.success.throttle_machines`
Emitted for successful calls through the breaker.

```ruby
# Payload:
{
  key: "payment_gateway",
  state: :closed
}
```

#### `circuit_breaker.failure.throttle_machines`
Emitted when a call fails (contributes to opening).

```ruby
# Payload:
{
  key: "payment_gateway",
  state: :closed,
  error_class: "Net::ReadTimeout",
  error_message: "Connection timed out"
}
```

#### `circuit_breaker.rejected.throttle_machines`
Emitted when a request is rejected due to open circuit.

```ruby
# Payload:
{
  key: "payment_gateway",
  failure_threshold: 5,
  timeout: 300
}
```

### Advanced Feature Events

#### `cascade.triggered.throttle_machines`
Emitted when a cascade failure propagates to dependent services.

```ruby
# Payload:
{
  primary_key: "database",
  cascaded_key: "user_service"
}
```

#### `hedged_request.started.throttle_machines`
Emitted when a hedged request begins.

```ruby
# Payload:
{
  request_id: "70123456789-1234567890.123",
  max_attempts: 3
}
```

#### `hedged_request.winner.throttle_machines`
Emitted when an attempt wins the race.

```ruby
# Payload:
{
  request_id: "70123456789-1234567890.123",
  winning_attempt: 1,
  duration: 0.127  # seconds
}
```

---

## 🎯 Integration Examples

### Rails Application Monitoring

```ruby
# config/initializers/throttle_machines_instrumentation.rb

# Log important events
ActiveSupport::Notifications.subscribe("rate_limit.throttled.throttle_machines") do |*, payload|
  Rails.logger.warn "Rate limit hit: #{payload[:key]} - retry after #{payload[:retry_after]}s"
  
  # Track in your metrics system
  StatsD.increment("rate_limits.exceeded", tags: ["key:#{payload[:key]}"])
end

ActiveSupport::Notifications.subscribe("circuit_breaker.opened.throttle_machines") do |*, payload|
  Rails.logger.error "Circuit opened: #{payload[:key]} after #{payload[:failure_count]} failures"
  
  # Send alert
  AlertManager.notify(
    severity: :critical,
    message: "Circuit breaker opened for #{payload[:key]}",
    details: payload
  )
end

# Track performance metrics
ActiveSupport::Notifications.subscribe("rate_limit.checked.throttle_machines") do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  
  StatsD.timing("rate_limit.check_duration", duration, 
    tags: ["algorithm:#{payload[:algorithm]}", "allowed:#{payload[:allowed]}"]
  )
end
```

### Custom Logging

```ruby
class ThrottleLogger
  def self.setup
    ActiveSupport::Notifications.subscribe(/throttle_machines/) do |name, start, finish, id, payload|
      event_type = name.split('.').first(2).join('.')
      
      log_entry = {
        timestamp: Time.now.iso8601,
        event: event_type,
        duration_ms: ((finish - start) * 1000).round(2),
        payload: payload
      }
      
      # Log as JSON for structured logging
      Rails.logger.info log_entry.to_json
    end
  end
end

ThrottleLogger.setup
```

### APM Integration

```ruby
# New Relic
ActiveSupport::Notifications.subscribe(/throttle_machines/) do |name, start, finish, id, payload|
  NewRelic::Agent.record_custom_event("ThrottleMachines", {
    event_type: name,
    duration: finish - start,
    **payload
  })
end

# DataDog
ActiveSupport::Notifications.subscribe(/throttle_machines/) do |name, start, finish, id, payload|
  Datadog::Tracing.trace("throttle_machines.#{name}") do |span|
    span.set_tags(payload)
  end
end
```

### Conditional Actions

```ruby
# Auto-scale when rate limits are frequently hit
rate_limit_hits = Concurrent::AtomicFixnum.new(0)

ActiveSupport::Notifications.subscribe("rate_limit.throttled.throttle_machines") do |*, payload|
  count = rate_limit_hits.increment
  
  if count > 100 # 100 throttles in the time window
    AutoScaler.scale_up("api_servers", increment: 2)
    rate_limit_hits.value = 0 # Reset counter
  end
end

# Circuit breaker recovery notifications
ActiveSupport::Notifications.subscribe("circuit_breaker.closed.throttle_machines") do |*, payload|
  SlackNotifier.notify(
    channel: "#ops",
    message: "🟢 Circuit breaker recovered: #{payload[:key]}"
  )
end
```

---

## 🔧 Configuration

### Disabling Instrumentation

```ruby
# Disable all instrumentation (for performance-critical paths)
ThrottleMachines.configure do |config|
  config.instrumentation_enabled = false
end
```

### Custom Backend

```ruby
# Use a custom instrumentation backend
class MyInstrumentationBackend
  def instrument(name, payload = {})
    # Your custom implementation
    MyMetrics.track(name, payload)
    yield if block_given?
  end
end

ThrottleMachines.configure do |config|
  config.instrumentation_backend = MyInstrumentationBackend.new
end
```

---

## 📈 Performance Impact

Instrumentation has minimal performance impact:
- Events are only emitted if there are subscribers
- Payload creation is lazy when possible
- No external I/O in the hot path

Benchmark results:
- Without instrumentation: 0.002ms per check
- With instrumentation (no subscribers): 0.003ms per check
- With instrumentation (with subscriber): 0.005ms per check

---

## 🎮 Testing with Instrumentation

```ruby
# In your tests
class InstrumentationTest < Minitest::Test
  def setup
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(/throttle_machines/) do |name, _, _, _, payload|
      @events << { name: name, payload: payload }
    end
  end
  
  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end
  
  def test_rate_limit_events
    limiter = ThrottleMachines.limiter("test", limit: 1, period: 60)
    
    limiter.throttle! { "first" }
    assert_equal "rate_limit.allowed.throttle_machines", @events.last[:name]
    
    assert_raises(ThrottleMachines::ThrottledError) do
      limiter.throttle! { "second" }
    end
    assert_equal "rate_limit.throttled.throttle_machines", @events.last[:name]
  end
end
```

---

## 🚀 Best Practices

1. **Subscribe to specific events** rather than all events for better performance
2. **Keep subscribers fast** - avoid blocking I/O in event handlers
3. **Use structured logging** for easier parsing and analysis
4. **Set up alerts** for critical events like circuit breakers opening
5. **Track trends** over time to identify patterns and optimize limits

---

**"In space, telemetry is the difference between a successful mission and floating debris."**

*— Mission Control Handbook*
