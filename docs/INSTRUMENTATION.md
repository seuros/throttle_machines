# 📡 Instrumentation Guide

> **Mission Telemetry** - Monitor your rate limiting and circuit breaking in real-time

ThrottleMachines reports what its limiters, hedged requests and Rack middleware
decide through `ActiveSupport::Notifications`. Circuits are BreakerMachines
circuits, which publish their own events (see [Circuit Events](#circuit-events)).

**Every period, wait and duration in a payload is Integer nanoseconds**, the
unit the whole gem speaks. Divide by `ThrottleMachines::NS_PER_SECOND` only
where a human reads the number.

```ruby
NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000
```

---

## 🚀 Quick Start

```ruby
# Instrumentation is on by default
ThrottleMachines.configure do |config|
  config.instrumentation_enabled = true
end

# Subscribe to every ThrottleMachines event
ActiveSupport::Notifications.subscribe(/\.throttle_machines\z/) do |name, _start, _finish, _id, payload|
  Rails.logger.info "[#{name}] #{payload}"
end
```

---

## 📊 Available Events

Limiter and hedged-request events are named `<event>.throttle_machines`.

### Rate Limiter Events

#### `rate_limit.checked.throttle_machines`
Emitted by `Limiter#allow?`, the non-consuming check.

```ruby
# Payload:
{
  key: "api:user:123",
  limit: 100,
  period: 60 * NS,     # Integer nanoseconds
  algorithm: :gcra,    # :fixed_window, :gcra or :token_bucket
  allowed: true,
  remaining: nil       # allow? does not count what is left
}
```

#### `rate_limit.allowed.throttle_machines`
Emitted when `Limiter#throttle!` admits a call.

```ruby
# Payload:
{
  key: "api:user:123",
  limit: 100,
  period: 60 * NS,
  algorithm: :gcra,
  remaining: 94        # calls still admitted now
}
```

#### `rate_limit.throttled.throttle_machines` ⚠️
Emitted when `Limiter#throttle!` refuses a call, just before it raises
`ThrottleMachines::ThrottledError`.

```ruby
# Payload:
{
  key: "api:user:123",
  limit: 100,
  period: 60 * NS,
  algorithm: :gcra,
  retry_after: 45_200_000_000  # Integer nanoseconds until a call is admitted
}
```

### Hedged Request Events

#### `hedged_request.started.throttle_machines`
Emitted when `HedgedRequest#run` (or `ThrottleMachines.hedged_request`) starts.

```ruby
# Payload:
{
  request_id: "70123456789-81234567890123",  # object id and start instant (ns)
  max_attempts: 3
}
```

#### `hedged_request.winner.throttle_machines`
Emitted when an attempt wins the race.

```ruby
# Payload:
{
  request_id: "70123456789-81234567890123",
  winning_attempt: 1,       # zero-based
  duration: 127_000_000     # Integer nanoseconds since the start
}
```

### Rack Middleware Events

`ThrottleMachines::RackMiddleware` publishes `<match_type>.throttle_machines`
through `RackMiddleware.notifier` (`ActiveSupport::Notifications` by default;
set it to `nil` to silence the middleware). The payload is `{ request: }`, and
the details are on the request's env, Rack::Attack style:

| Event | Emitted when | `env['rack.attack.match_data']` |
|-------|--------------|--------------------------------|
| `throttle.throttle_machines` | a throttle refuses | `discriminator`, `count`, `limit`, `period` (ns), `retry_after` (ns) |
| `fail2ban.throttle_machines` | a banned client calls | `discriminator`, `maxretry`, `findtime` (ns), `bantime` (ns), `failures`, `time_until_unban` (ns) |
| `blocklist.throttle_machines` | a blocklist matches | none (`rack.attack.matched` names the rule) |
| `safelist.throttle_machines` | a safelist matches | none |
| `track.throttle_machines` | a track matches | `discriminator`, plus `count`, `limit`, `period` (ns) when it has a limit |

```ruby
ActiveSupport::Notifications.subscribe('throttle.throttle_machines') do |*, payload|
  env = payload[:request].env
  wait = env['rack.attack.match_data'][:retry_after].ceildiv(NS) # whole seconds, rounded up
  Rails.logger.warn "#{env['rack.attack.matched']} throttled #{env['rack.attack.match_discriminator']} for #{wait}s"
end
```

### Circuit Events

`Control#break_on`, `ThrottleMachines.break_circuit`, `AsyncBreaker` and the
fail2ban filter all run BreakerMachines circuits. ThrottleMachines adds no
circuit events of its own: BreakerMachines publishes `breaker_machines.<event>`
(prefix, not suffix) while `BreakerMachines.config.log_events` is true, the
default.

| Event | Payload |
|-------|---------|
| `breaker_machines.opened` 🚨 | `circuit:` |
| `breaker_machines.half_opened` | `circuit:` |
| `breaker_machines.closed` ✅ | `circuit:` |
| `breaker_machines.rejected` | `circuit:`, `refusal:` (`:open`, `:busy` or `:full`) |
| `breaker_machines.callback_error` | `circuit:`, `callback:`, `error:` |
| `breaker_machines.storage_error` | `circuit:`, `error:` |

The circuit's name is its key: `Control.new("payment_gateway")` builds a
circuit named `"payment_gateway"`, and a fail2ban filter `"login"` builds one
per client, named `"fail2ban:login:<discriminator>"`.

```ruby
ActiveSupport::Notifications.subscribe(/\Abreaker_machines\./) do |name, *, payload|
  Rails.logger.info "[#{name}] #{payload[:circuit]}"
end

BreakerMachines.setup_notifications # or let BreakerMachines log opened/closed/half_opened itself
```

---

## 🎯 Integration Examples

### Rails Application Monitoring

```ruby
# config/initializers/throttle_machines_instrumentation.rb
NS = ThrottleMachines::NS_PER_SECOND

# Log important events
ActiveSupport::Notifications.subscribe("rate_limit.throttled.throttle_machines") do |*, payload|
  wait = payload[:retry_after].ceildiv(NS)
  Rails.logger.warn "Rate limit hit: #{payload[:key]} - retry after #{wait}s"

  # Track in your metrics system
  StatsD.increment("rate_limits.exceeded", tags: ["key:#{payload[:key]}"])
end

ActiveSupport::Notifications.subscribe("breaker_machines.opened") do |*, payload|
  Rails.logger.error "Circuit opened: #{payload[:circuit]}"

  # Send alert
  AlertManager.notify(
    severity: :critical,
    message: "Circuit breaker opened for #{payload[:circuit]}",
    details: payload
  )
end

# Track how long a check takes. The event's own timing is ActiveSupport's
# (`event.duration` is Float milliseconds), not a ThrottleMachines span.
ActiveSupport::Notifications.subscribe("rate_limit.checked.throttle_machines") do |event|
  StatsD.timing("rate_limit.check_duration", event.duration,
    tags: ["algorithm:#{event.payload[:algorithm]}", "allowed:#{event.payload[:allowed]}"]
  )
end
```

### Custom Logging

```ruby
class ThrottleLogger
  def self.setup
    ActiveSupport::Notifications.subscribe(/\.throttle_machines\z/) do |name, *, payload|
      log_entry = {
        timestamp: Time.now.iso8601,
        event: name.delete_suffix('.throttle_machines'),
        payload: payload.except(:request) # a Rack request does not serialize
      }

      # Log as JSON for structured logging; spans stay Integer nanoseconds
      Rails.logger.info log_entry.to_json
    end
  end
end

ThrottleLogger.setup
```

### APM Integration

```ruby
# New Relic
ActiveSupport::Notifications.subscribe(/\Arate_limit\..*\.throttle_machines\z/) do |name, *, payload|
  NewRelic::Agent.record_custom_event("ThrottleMachines", { event_type: name, **payload })
end

# DataDog
ActiveSupport::Notifications.subscribe(/\Arate_limit\..*\.throttle_machines\z/) do |name, *, payload|
  Datadog::Tracing.trace("throttle_machines.#{name}") do |span|
    span.set_tags(payload)
  end
end
```

### Conditional Actions

```ruby
# Auto-scale when rate limits are frequently hit
rate_limit_hits = Concurrent::AtomicFixnum.new(0)

ActiveSupport::Notifications.subscribe("rate_limit.throttled.throttle_machines") do |*, _payload|
  count = rate_limit_hits.increment

  if count > 100 # 100 throttles in the time window
    AutoScaler.scale_up("api_servers", increment: 2)
    rate_limit_hits.value = 0 # Reset counter
  end
end

# Circuit recovery notifications
ActiveSupport::Notifications.subscribe("breaker_machines.closed") do |*, payload|
  SlackNotifier.notify(
    channel: "#ops",
    message: "🟢 Circuit breaker recovered: #{payload[:circuit]}"
  )
end
```

---

## 🔧 Configuration

### Disabling Instrumentation

```ruby
# Silence limiter and hedged-request events
ThrottleMachines.configure do |config|
  config.instrumentation_enabled = false
end

# Silence the Rack middleware
ThrottleMachines::RackMiddleware.notifier = nil

# Silence circuit events
BreakerMachines.configure { |config| config.log_events = false }
```

### Custom Backend

```ruby
# Anything answering `instrument(name, payload)` and yielding a block it is given
class MyInstrumentationBackend
  def instrument(name, payload = {})
    MyMetrics.track(name, payload)
    yield if block_given?
  end
end

ThrottleMachines.configure do |config|
  config.instrumentation_backend = MyInstrumentationBackend.new
end
```

The backend receives the full name (`"rate_limit.allowed.throttle_machines"`).
It replaces `ActiveSupport::Notifications` for limiter and hedged-request
events only; the middleware publishes through `RackMiddleware.notifier`.

---

## 📈 Performance Impact

- With no subscriber, `ActiveSupport::Notifications` publishes nothing; each
  event costs the payload hash and the notifier's subscriber lookup.
- An admission's `remaining` is the count the check itself answered, so it
  costs no storage read and cannot race another caller. A refusal's
  `retry_after` costs one more storage read, made only while instrumentation
  is enabled with a backend set. Disabled, `throttle!` does no storage work
  beyond the check itself. Enabled, the read happens even when nothing
  subscribes, so set `config.instrumentation_enabled = false` when no one
  listens.
- No event does I/O of its own. A slow subscriber runs inline, in the request.

---

## 🎮 Testing with Instrumentation

```ruby
# In your tests
class InstrumentationTest < Minitest::Test
  NS = ThrottleMachines::NS_PER_SECOND

  def setup
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(/\.throttle_machines\z/) do |name, *, payload|
      @events << { name: name, payload: payload }
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end

  def test_rate_limit_events
    limiter = ThrottleMachines.limiter("test", limit: 1, period: 60 * NS)

    limiter.throttle! { "first" }
    assert_equal "rate_limit.allowed.throttle_machines", @events.last[:name]

    assert_raises(ThrottleMachines::ThrottledError) do
      limiter.throttle! { "second" }
    end
    assert_equal "rate_limit.throttled.throttle_machines", @events.last[:name]
    assert_kind_of Integer, @events.last[:payload][:retry_after] # nanoseconds
  end
end
```

---

## 🚀 Best Practices

1. **Subscribe to specific events** rather than all events for better performance
2. **Keep subscribers fast** - they run inline, inside the request
3. **Keep spans in nanoseconds** until display; round waits up (`ceildiv`), never down
4. **Set up alerts** for critical events like circuits opening
5. **Track trends** over time to identify patterns and optimize limits

---

**"In space, telemetry is the difference between a successful mission and floating debris."**

*— Mission Control Handbook*
