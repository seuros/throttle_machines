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

---

## 🛡️ Basic Shield Configuration

### Your First Shield Generator
```ruby
require 'throttle_machines'

# Create a basic shield system
shields = ThrottleMachines::Breaker.new("warp_core_shields",
  failure_threshold: 5,    # 5 hits before shields activate
  reset_timeout: 300,      # Shields stay up for 5 minutes
  storage: ThrottleMachines.configuration.storage
)

# Protected operation
begin
  shields.run do
    engage_warp_drive!  # Protected system
  end
rescue ThrottleMachines::CircuitOpenError => e
  puts "🛡️ Shields are UP! System protected. Retry in #{e.retry_after} seconds"
end
```

---

## 🎯 Shield Patterns

### Pattern 1: The API Defense Grid
```ruby
class ExternalAPIShield
  def initialize(api_name)
    @api_name = api_name
    @shields = ThrottleMachines::Breaker.new(
      "api_shield_#{api_name}",
      failure_threshold: 3,    # 3 strikes
      reset_timeout: 60,       # 1 minute cooldown
      storage: ThrottleMachines.configuration.storage
    )
  end
  
  def call_api(&block)
    @shields.run do
      response = yield
      
      # Manual failure detection
      if response.status >= 500
        @shields.record_failure
        raise "API returned #{response.status}"
      end
      
      response
    end
  rescue ThrottleMachines::CircuitOpenError => e
    # Return cached/fallback data when shields are up
    {
      cached: true,
      data: fetch_cached_response,
      shield_status: "active",
      retry_after: e.retry_after
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
    @shields = ThrottleMachines::Breaker.new(
      "database_shields",
      failure_threshold: 5,
      reset_timeout: 30,  # Quick recovery for databases
      storage: ThrottleMachines.configuration.storage
    )
  end
  
  def query(&block)
    @shields.run do
      # Set aggressive timeout for database queries
      ActiveRecord::Base.connection.execute("SET statement_timeout = '5s'")
      yield
    end
  rescue ActiveRecord::StatementTimeout => e
    @shields.record_failure
    raise DatabaseOverloadError, "Query timeout - shields activated"
  rescue ThrottleMachines::CircuitOpenError => e
    # Use read replica or cache when primary is protected
    Rails.logger.warn "Database shields active - using read replica"
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end
end

# Usage in your application
class UserService
  def self.find_user(id)
    DatabaseShield.new.query do
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
    @primary_shield = ThrottleMachines::Breaker.new(
      "primary_shield",
      failure_threshold: 10,
      reset_timeout: 60
    )
    
    @secondary_shield = ThrottleMachines::Breaker.new(
      "secondary_shield", 
      failure_threshold: 5,
      reset_timeout: 300  # Longer recovery time
    )
    
    @emergency_shield = ThrottleMachines::Breaker.new(
      "emergency_shield",
      failure_threshold: 3,
      reset_timeout: 600  # 10 minute lockdown
    )
  end
  
  def execute_critical_operation(&block)
    # Try primary systems first
    @primary_shield.run { return yield }
  rescue ThrottleMachines::CircuitOpenError
    # Primary shields up, try secondary systems
    begin
      @secondary_shield.run { return degraded_operation(&block) }
    rescue ThrottleMachines::CircuitOpenError
      # Secondary shields up, emergency protocols
      @emergency_shield.run { return emergency_fallback }
    end
  end
  
  private
  
  def degraded_operation(&block)
    # Run with reduced functionality
    with_timeout(1) { yield }
  end
  
  def emergency_fallback
    # Minimal safe response
    { status: "emergency_mode", message: "All systems protected" }
  end
end
```

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
    
    ThrottleMachines::Breaker.new(
      "adaptive_shield_#{@service_name}",
      failure_threshold: threshold,
      reset_timeout: calculate_recovery_time,
      storage: ThrottleMachines.configuration.storage
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
    peak_hours? ? 300 : 60
  end
  
  def peak_hours?
    hour = Time.current.hour
    (7..9).include?(hour) || (17..19).include?(hour)
  end
end
```

### Shield Monitoring & Telemetry
```ruby
class ShieldTelemetry
  def self.monitor(shield_name, &block)
    start_time = Time.current
    shield_state = :transparent
    
    begin
      result = yield
      record_success(shield_name, Time.current - start_time)
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
      emit_telemetry(shield_name, shield_state, Time.current - start_time)
    end
  end
  
  private
  
  def self.record_success(shield_name, duration)
    StatsD.timing("shields.#{shield_name}.success", duration)
    StatsD.increment("shields.#{shield_name}.requests.success")
  end
  
  def self.record_shield_activation(shield_name, retry_after)
    StatsD.increment("shields.#{shield_name}.activated")
    StatsD.gauge("shields.#{shield_name}.retry_after", retry_after)
    
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
      duration_ms: (duration * 1000).round,
      timestamp: Time.current.iso8601
    }.to_json)
  end
end

# Usage with telemetry
class MonitoredService
  def call_external_api
    ShieldTelemetry.monitor("external_api") do
      @shields.run do
        perform_api_call
      end
    end
  end
end
```

---

## 🎮 Shield Control Interface

### Manual Shield Control
```ruby
class ShieldControl
  def initialize(breaker)
    @breaker = breaker
  end
  
  # Force shields up (emergency protocol)
  def raise_shields!
    @breaker.trip!
    broadcast_alert("Shields manually raised by command")
  end
  
  # Attempt shield lowering (with safety check)
  def lower_shields!
    if safe_to_lower?
      @breaker.reset!
      broadcast_alert("Shields lowered - systems normal")
    else
      broadcast_alert("Cannot lower shields - threats detected")
      false
    end
  end
  
  # Shield status report
  def status
    {
      state: @breaker.status_name,
      failures: @breaker.stats.failure_count,
      last_failure: @breaker.last_failure_time,
      auto_reset_at: @breaker.reset_at,
      health: calculate_shield_health
    }
  end
  
  private
  
  def safe_to_lower?
    # Check if it's safe to lower shields
    recent_failures = @breaker.stats.failure_count
    time_since_failure = Time.current - (@breaker.last_failure_time || 1.hour.ago)
    
    recent_failures < 2 && time_since_failure > 5.minutes
  end
  
  def calculate_shield_health
    case @breaker.status_name
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
    @shield = ThrottleMachines::Breaker.new(
      "payment_processor",
      failure_threshold: 3,    # Very sensitive
      reset_timeout: 1800,     # 30 minutes - payment systems need time
      storage: ThrottleMachines.configuration.storage
    )
  end
  
  def process_payment(amount, customer)
    @shield.run do
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
      retry_after: e.retry_after,
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
    @shield = ThrottleMachines::Breaker.new(
      "ai_service",
      failure_threshold: 5,
      reset_timeout: 120,  # Quick recovery for AI services
      storage: ThrottleMachines.configuration.storage
    )
    
    # Also add rate limiting to prevent abuse
    @rate_limiter = ThrottleMachines.limiter(
      "ai_rate_limit",
      limit: 100,
      period: 3600,
      algorithm: :gcra
    )
  end
  
  def generate_response(prompt)
    # Check rate limit first
    unless @rate_limiter.allowed?
      return {
        error: "Rate limit exceeded",
        retry_after: @rate_limiter.retry_after
      }
    end
    
    # Then check shields
    @shield.run do
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
    breaker = ThrottleMachines.breakers[breaker_name]
    
    {
      current_state: breaker.status_name,
      uptime_percentage: calculate_uptime(breaker),
      failure_rate: calculate_failure_rate(breaker),
      mttr: mean_time_to_recovery(breaker),
      protection_events: protection_timeline(breaker)
    }
  end
  
  private
  
  def self.calculate_uptime(breaker)
    total_time = Time.current - breaker.created_at
    open_time = breaker.time_in_open_state
    
    ((total_time - open_time) / total_time * 100).round(2)
  end
  
  def self.calculate_failure_rate(breaker)
    window = 1.hour.ago
    recent_failures = breaker.failures_since(window)
    total_calls = breaker.calls_since(window)
    
    return 0 if total_calls.zero?
    (recent_failures.to_f / total_calls * 100).round(2)
  end
  
  def self.mean_time_to_recovery(breaker)
    recoveries = breaker.recovery_times
    return 0 if recoveries.empty?
    
    (recoveries.sum / recoveries.size).round
  end
  
  def self.protection_timeline(breaker)
    breaker.state_changes.last(10).map do |change|
      {
        timestamp: change.timestamp,
        from_state: change.from,
        to_state: change.to,
        duration: change.duration
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
