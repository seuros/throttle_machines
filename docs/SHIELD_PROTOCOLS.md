# 🛡️ Shield Protocols

> **Circuit Breakers & Defensive Systems** - When your shields are the only thing between you and the void

## Stardate 2025.319 - The Shield Crisis

The year is 2025. Your microservices armada drifts through the cold vacuum of cyberspace. Suddenly, alarms blare. The payment service is down. The authentication server is timing out. Database connections are dropping like meteorites in a gravity well.

And somewhere on the bridge, a junior engineer reaches for the console:

```ruby
def call_critical_service
  begin
    external_api.post(data)
  rescue
    sleep 1
    retry  # "Maybe it'll work this time?"
  end
end
```

The senior engineer's hand slams down on the emergency stop. "NO! You'll cascade the failure across the entire fleet!"

This is why we have shields.

---

## 🌌 Understanding Shield Technology

### The Analogy
Imagine your spacecraft's shields:
- **Normal Operation**: Shields are transparent, all traffic passes through
- **Under Attack**: After taking several hits, shields activate (circuit opens)
- **Protection Mode**: All incoming damage is deflected for a cooldown period
- **Recovery**: Shields gradually lower as systems stabilize

Circuit breakers work the same way with your services!

ThrottleMachines does not build its own shield generators: its circuits are
[BreakerMachines](https://github.com/seuros/breaker_machines) circuits.
`ThrottleMachines::Breakers.policy(failures, window, cooldown)` shapes the
`BreakerMachines::Policy` they run: open after `failures` within `window`, stay
open exactly `cooldown` (no jitter), then close on one successful probe. Every
span is **Integer nanoseconds**.

---

## 🛡️ Basic Shield Configuration

### Your First Shield Generator
```ruby
require 'throttle_machines'

NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000

# Create a basic shield system
shields = BreakerMachines::Circuit.new("warp_core_shields",
  ThrottleMachines::Breakers.policy(
    5,        # 5 hits before shields activate...
    60 * NS,  # ...within one minute
    300 * NS  # Shields stay up for 5 minutes
  )
)

# Protected operation
begin
  shields.call do
    engage_warp_drive!  # Protected system
  end
rescue ThrottleMachines::CircuitOpenError => e
  # retry_after is Integer nanoseconds (nil when the lone probe slot is busy)
  puts "🛡️ Shields are UP! System protected. Retry in #{e.retry_after} ns"
end
```

Need a shield exactly once, by name, shared across the whole ship? The registry
keeps one per key:

```ruby
ThrottleMachines.break_circuit("warp_core_shields", failures: 5, within: 60 * NS, timeout: 300 * NS) do
  engage_warp_drive!
end
```

---

## 🎯 Shield Patterns

### Pattern 1: The API Defense Grid
```ruby
class ExternalAPIShield
  def initialize(api_name)
    @api_name = api_name
    @shields = BreakerMachines::Circuit.new(
      "api_shield_#{api_name}",
      ThrottleMachines::Breakers.policy(
        3,        # 3 strikes
        60 * NS,  # within a minute
        60 * NS   # 1 minute cooldown
      )
    )
  end

  def call_api(&block)
    @shields.call do
      response = yield

      # Manual failure detection: anything raised inside the block is a hit
      raise "API returned #{response.status}" if response.status >= 500

      response
    end
  rescue ThrottleMachines::CircuitOpenError => e
    # Return cached/fallback data when shields are up
    {
      cached: true,
      data: fetch_cached_response,
      shield_status: "active",
      retry_after: e.retry_after # Integer ns
    }
  end

  private

  def fetch_cached_response
    # Return last known good response
    Rails.cache.read("#{@api_name}_fallback") || { error: "No cached data" }
  end
end

# Usage
payment_shield = ExternalAPIShield.new("stripe")
result = payment_shield.call_api do
  Stripe::Charge.create(amount: 1000, currency: "usd")
end
```

### Pattern 2: The Database Defense Matrix
```ruby
class DatabaseShield
  def initialize
    @shields = BreakerMachines::Circuit.new(
      "database_shields",
      ThrottleMachines::Breakers.policy(5, 60 * NS, 30 * NS) # Quick recovery for databases
    )
  end

  def query(&block)
    @shields.call do
      # Set aggressive timeout for database queries
      ActiveRecord::Base.connection.execute("SET statement_timeout = '5s'")
      yield
    end
  rescue ActiveRecord::StatementTimeout
    # Already counted as a hit by the circuit; translate for the crew
    raise DatabaseOverloadError, "Query timeout - shields activated"
  rescue ThrottleMachines::CircuitOpenError
    # Use read replica or cache when primary is protected
    Rails.logger.warn "Database shields active - using read replica"
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end
end

# One shield generator for the whole ship: a new circuit per call never trips
DATABASE_SHIELD = DatabaseShield.new

# Usage in your application
class UserService
  def self.find_user(id)
    DATABASE_SHIELD.query do
      User.find(id)
    end
  end
end
```

### Pattern 3: The Cascading Shield Array
```ruby
class CascadingDefenseSystem
  def initialize
    # Multiple shield layers with different sensitivities
    @primary_shield = BreakerMachines::Circuit.new(
      "primary_shield",
      ThrottleMachines::Breakers.policy(10, 60 * NS, 60 * NS)
    )

    @secondary_shield = BreakerMachines::Circuit.new(
      "secondary_shield",
      ThrottleMachines::Breakers.policy(5, 60 * NS, 300 * NS), # Longer recovery time
      timeout: 1 * NS # cooperative: the block checks DeadlineMachines
    )

    @emergency_shield = BreakerMachines::Circuit.new(
      "emergency_shield",
      ThrottleMachines::Breakers.policy(3, 60 * NS, 600 * NS) # 10 minute lockdown
    )
  end

  def execute_critical_operation(&block)
    # Try primary systems first. Never `return` from inside the block:
    # the circuit would abandon the call instead of recording the success.
    @primary_shield.call(&block)
  rescue ThrottleMachines::CircuitOpenError
    # Primary shields up, try secondary systems
    begin
      @secondary_shield.call { degraded_operation(&block) }
    rescue ThrottleMachines::CircuitOpenError
      # Secondary shields up, emergency protocols
      @emergency_shield.call { emergency_fallback }
    end
  end

  private

  def degraded_operation(&block)
    # Run with reduced functionality, inside the secondary shield's 1 s budget
    DeadlineMachines.check!
    yield
  end

  def emergency_fallback
    # Minimal safe response
    { status: "emergency_mode", message: "All systems protected" }
  end
end
```

A circuit can also carry its own fallbacks: `fallback:` takes a Proc (called
with the error), an Array of them tried in order, or a plain value.

---

## 🔧 Advanced Shield Configuration

### Adaptive Shield Strength
```ruby
class AdaptiveShield
  def initialize(service_name)
    @service_name = service_name
    @base_threshold = 5
  end

  def create_shield
    # Adjust shield sensitivity based on time of day
    threshold = calculate_dynamic_threshold

    BreakerMachines::Circuit.new(
      "adaptive_shield_#{@service_name}",
      ThrottleMachines::Breakers.policy(threshold, 60 * NS, calculate_recovery_time)
    )
  end

  private

  def calculate_dynamic_threshold
    hour = Time.current.hour

    case hour
    when 0..6   # Night shift - more sensitive
      @base_threshold - 2
    when 7..9   # Morning rush - normal
      @base_threshold
    when 10..16 # Business hours - less sensitive
      @base_threshold + 3
    when 17..19 # Evening rush - normal
      @base_threshold
    else        # Evening - moderate
      @base_threshold + 1
    end
  end

  def calculate_recovery_time
    # Longer recovery during peak hours
    peak_hours? ? 300 * NS : 60 * NS
  end

  def peak_hours?
    hour = Time.current.hour
    (7..9).include?(hour) || (17..19).include?(hour)
  end
end
```

### Shield Monitoring & Telemetry
```ruby
MS = 1_000_000

class ShieldTelemetry
  def self.monitor(shield_name, &block)
    start_time = ThrottleMachines.monotonic_time
    shield_state = :transparent

    begin
      result = yield
      record_success(shield_name, ThrottleMachines.monotonic_time - start_time)
      result
    rescue ThrottleMachines::CircuitOpenError => e
      shield_state = :active
      record_shield_activation(shield_name, e.retry_after)
      raise
    rescue => e
      shield_state = :damaged
      record_failure(shield_name, e.class.name)
      raise
    ensure
      emit_telemetry(shield_name, shield_state, ThrottleMachines.monotonic_time - start_time)
    end
  end

  private

  def self.record_success(shield_name, duration)
    StatsD.timing("shields.#{shield_name}.success", duration / MS) # StatsD speaks ms
    StatsD.increment("shields.#{shield_name}.requests.success")
  end

  def self.record_shield_activation(shield_name, retry_after)
    StatsD.increment("shields.#{shield_name}.activated")
    StatsD.gauge("shields.#{shield_name}.retry_after_ns", retry_after || 0)

    # Alert the crew!
    AlertSystem.notify(
      level: :warning,
      message: "Shield system '#{shield_name}' has been activated",
      retry_after: retry_after
    )
  end

  def self.record_failure(shield_name, error_type)
    StatsD.increment("shields.#{shield_name}.failures.#{error_type}")
  end

  def self.emit_telemetry(shield_name, state, duration)
    Rails.logger.info({
      event: "shield_telemetry",
      shield: shield_name,
      state: state,
      duration_ns: duration,
      timestamp: Time.current.iso8601
    }.to_json)
  end
end

# Usage with telemetry
class MonitoredService
  def call_external_api
    ShieldTelemetry.monitor("external_api") do
      @shields.call do
        perform_api_call
      end
    end
  end
end
```

Circuits also publish their own transitions through ActiveSupport::Notifications:
`breaker_machines.opened`, `breaker_machines.closed`,
`breaker_machines.half_opened` and `breaker_machines.rejected`, each with
`circuit:` in the payload.

---

## 🎮 Shield Control Interface

### Manual Shield Control
```ruby
class ShieldControl
  def initialize(breaker)
    @breaker = breaker
  end

  # Force shields up (emergency protocol), restarting the cooldown
  def raise_shields!
    @breaker.force_open
    broadcast_alert("Shields manually raised by command")
  end

  # Attempt shield lowering (with safety check)
  def lower_shields!
    if safe_to_lower?
      @breaker.force_close # keeps the failure window; `reset` would clear it
      broadcast_alert("Shields lowered - systems normal")
    else
      broadcast_alert("Cannot lower shields - threats detected")
      false
    end
  end

  # Shield status report
  def status
    stats = @breaker.stats
    {
      state: @breaker.state,
      failures: stats.failure_count,
      last_failure_at: stats.last_failure_at, # Integer ns on the circuit's clock
      probe_in: @breaker.retry_after,         # Integer ns, nil unless open
      health: calculate_shield_health
    }
  end

  private

  def safe_to_lower?
    # Check if it's safe to lower shields
    stats = @breaker.stats
    return true if stats.last_failure_at.nil?

    time_since_failure = @breaker.now - stats.last_failure_at
    stats.failure_count < 2 && time_since_failure > 5 * 60 * NS
  end

  def calculate_shield_health
    case @breaker.state
    when :closed
      "100% - All systems operational"
    when :open
      "0% - Shields at maximum"
    when :half_open
      "50% - Testing integrity"
    end
  end

  def broadcast_alert(message)
    ActionCable.server.broadcast("shield_status", {
      message: message,
      shield_name: @breaker.name,
      status: status
    })
  end
end
```

---

## 🛠️ Shield Patterns for Common Scenarios

### Payment Processing Shield
```ruby
class PaymentShield
  def initialize
    @shield = BreakerMachines::Circuit.new(
      "payment_processor",
      ThrottleMachines::Breakers.policy(
        3,         # Very sensitive
        60 * NS,
        1800 * NS  # 30 minutes - payment systems need time
      )
    )
  end

  def process_payment(amount, customer)
    @shield.call do
      # Primary payment processor
      Stripe::Charge.create(
        amount: amount,
        customer: customer,
        metadata: { protected: true }
      )
    end
  rescue ThrottleMachines::CircuitOpenError => e
    # Fallback to secondary processor or queue
    PaymentQueue.enqueue(
      amount: amount,
      customer: customer,
      retry_after: e.retry_after, # Integer ns
      reason: "Primary processor shields active"
    )

    {
      queued: true,
      message: "Payment queued for processing",
      reference: SecureRandom.uuid
    }
  end
end
```

### AI Service Shield
```ruby
class AIServiceShield
  def initialize
    @shield = BreakerMachines::Circuit.new(
      "ai_service",
      ThrottleMachines::Breakers.policy(5, 60 * NS, 120 * NS) # Quick recovery for AI services
    )

    # Also add rate limiting to prevent abuse
    @rate_limiter = ThrottleMachines.limiter(
      "ai_rate_limit",
      limit: 100,
      period: 3600 * NS,
      algorithm: :gcra
    )
  end

  def generate_response(prompt)
    # Check (and consume) the rate limit first, outside the shield:
    # a ThrottledError raised inside it would count as a hit
    begin
      @rate_limiter.throttle!
    rescue ThrottleMachines::ThrottledError => e
      return {
        error: "Rate limit exceeded",
        retry_after: e.retry_after # Integer ns
      }
    end

    # Then check shields
    @shield.call do
      response = OpenAI::Client.new.completions(
        model: "gpt-4",
        prompt: prompt,
        max_tokens: 150
      )

      # Cache successful responses
      cache_response(prompt, response)
      response
    end
  rescue ThrottleMachines::CircuitOpenError => e
    # Return cached response if available
    cached = fetch_cached_response(prompt)
    cached || {
      error: "AI service temporarily unavailable",
      retry_after: e.retry_after,
      suggestion: "Try simpler query or wait"
    }
  end
end
```

---

## 📊 Shield Analytics

```ruby
class ShieldAnalytics
  def self.report(breaker_name)
    breaker = BreakerMachines.registry.find(breaker_name)
    return nil unless breaker

    stats = breaker.stats
    {
      current_state: breaker.state,
      failure_rate: calculate_failure_rate(stats),
      open_for: ThrottleMachines::Breakers.since(breaker), # Integer ns, nil unless open
      probe_in: breaker.retry_after,                      # Integer ns, nil unless open
      protection_events: protection_timeline(breaker),
      summary: breaker.summary
    }
  end

  private

  # Failure share of the outcomes still inside the circuit's window
  def self.calculate_failure_rate(stats)
    total_calls = stats.failure_count + stats.success_count
    return 0 if total_calls.zero?

    (stats.failure_count.fdiv(total_calls) * 100).round(2)
  end

  # The newest recorded outcomes, oldest first. For the transition history,
  # subscribe to breaker_machines.opened / closed / half_opened instead.
  def self.protection_timeline(breaker)
    breaker.events(10).map do |event|
      {
        at: event.at,           # Integer ns on the circuit's clock
        outcome: event.outcome, # :success or :failure
        took: event.took        # Integer ns
      }
    end
  end
end
```

---

## 🚀 Next Missions

- **[🌍 Planetary Integration](PLANETARY_INTEGRATION.md)** - Rails and Rack setup
- **[📡 Telemetry](TELEMETRY.md)** - Monitoring your shields
- **[🎮 Command Examples](COMMAND_EXAMPLES.md)** - Real battle scenarios

---

**"Shields are not about preventing all damage - they're about surviving long enough to adapt and overcome."**

*— Shield Operations Manual, Chapter 7*
