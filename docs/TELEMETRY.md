# 📡 Telemetry

> **Monitoring & Instrumentation** - Because what you can't measure, you can't defend against

In the vast darkness of space, telemetry is your eyes and ears. This guide shows you how to monitor your ThrottleMachines deployment, track performance, and detect anomalies before they become catastrophes.

---

## 🌌 Telemetry Overview

### What to Monitor
- **Request rates** - Current traffic patterns
- **Limit violations** - When and why requests are blocked
- **Circuit breaker states** - Shield status across your fleet
- **Performance metrics** - Response times and resource usage
- **Storage health** - Redis connectivity and latency

---

## 📊 Basic Instrumentation

### ActiveSupport::Notifications Integration

Every limiter decision is published as `<event>.throttle_machines` through `ActiveSupport::Notifications` (or `config.instrumentation_backend`, anything answering `instrument`). Payload periods, `retry_after` and durations are Integer nanoseconds.

| Event | Payload |
|-------|---------|
| `rate_limit.checked.throttle_machines` (`allow?`) | `key`, `limit`, `period`, `algorithm`, `allowed`, `remaining` (nil) |
| `rate_limit.allowed.throttle_machines` (`throttle!` admitted) | `key`, `limit`, `period`, `algorithm`, `remaining` |
| `rate_limit.throttled.throttle_machines` (`throttle!` refused) | `key`, `limit`, `period`, `algorithm`, `retry_after` |
| `hedged_request.started.throttle_machines` | `request_id`, `max_attempts` |
| `hedged_request.winner.throttle_machines` | `request_id`, `winning_attempt`, `duration` |

Rate limit events are instrumented without a block, so `finish - start` is zero: time the work yourself. Circuits are BreakerMachines' business and publish under its own prefix: `breaker_machines.opened`, `.closed`, `.half_opened` (payload `circuit:`) and `breaker_machines.rejected` (`circuit:`, `refusal:`).

```ruby
# config/initializers/throttle_telemetry.rb
NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000
MS = 1_000_000

# Subscribe to all limiter and hedged request events
ActiveSupport::Notifications.subscribe(/\.throttle_machines\z/) do |name, _start, _finish, _id, payload|
  case name
  when "rate_limit.checked.throttle_machines", "rate_limit.allowed.throttle_machines"
    allowed = payload.fetch(:allowed, true)
    Rails.logger.info "⚡ Rate limit checked: #{payload[:key]} - Allowed: #{allowed}"

    # Send to metrics system
    StatsD.increment("throttle.checks", tags: ["allowed:#{allowed}", "algorithm:#{payload[:algorithm]}"])

  when "rate_limit.throttled.throttle_machines"
    StatsD.increment("throttle.checks", tags: ["allowed:false", "algorithm:#{payload[:algorithm]}"])
    StatsD.histogram("throttle.retry_after_ms", payload[:retry_after] / MS)

  when "hedged_request.winner.throttle_machines"
    StatsD.histogram("hedged.duration_ms", payload[:duration] / MS,
                     tags: ["attempt:#{payload[:winning_attempt]}"])
  end
end

# Shield telemetry, straight from BreakerMachines
ActiveSupport::Notifications.subscribe(/\Abreaker_machines\./) do |name, _start, _finish, _id, payload|
  circuit = BreakerMachines::Registry.instance.find(payload[:circuit])

  case name
  when "breaker_machines.opened"
    Rails.logger.warn "🛡️ Circuit breaker opened: #{payload[:circuit]} - " \
                     "Failures: #{circuit&.stats&.failure_count}"

    # Alert operations team
    PagerDuty.trigger(
      "Circuit breaker #{payload[:circuit]} is open",
      details: circuit&.to_h
    )

  when "breaker_machines.closed"
    Rails.logger.info "✅ Circuit breaker reset: #{payload[:circuit]}"

    StatsD.event("Circuit breaker recovered",
                "#{payload[:circuit]} is operational again")
  end
end
```

### Rack Middleware Telemetry

`ThrottleMachines::RackMiddleware` publishes through its own `notifier` (`ThrottleMachines::RackMiddleware.notifier`, default `ActiveSupport::Notifications`) as `<match_type>.throttle_machines`, with the request as the only payload: `throttle`, `blocklist`, `safelist`, `track`, `fail2ban`. The match details live on the env under `rack.attack.match_data` (spans in nanoseconds: `period`, `retry_after`, `findtime`, `bantime`, `time_until_unban`).

```ruby
RACK_EVENTS = /\A(throttle|blocklist|safelist|track|fail2ban)\.throttle_machines\z/

ActiveSupport::Notifications.subscribe(RACK_EVENTS) do |name, _start, _finish, _id, payload|
  request = payload[:request]
  data = request.env["rack.attack.match_data"] || {}

  case name
  when "throttle.throttle_machines"
    StatsD.increment("rack.throttled",
      tags: ["rule:#{request.env['rack.attack.matched']}", "path:#{request.path}", "ip:#{request.ip}"])

  when "blocklist.throttle_machines"
    Rails.logger.error "🚫 Blocked request from #{request.ip} to #{request.path}"
    SecurityAlert.notify("Blocked IP", ip: request.ip, path: request.path)

  when "fail2ban.throttle_machines"
    Rails.logger.error "🚫 Banned #{request.ip} for #{data[:time_until_unban].ceildiv(NS)}s more"

  when "safelist.throttle_machines"
    StatsD.increment("rack.safelisted")

  when "track.throttle_machines"
    # Log suspicious activity for analysis
    SuspiciousActivity.record(
      ip: request.ip,
      path: request.path,
      user_agent: request.user_agent
    )
  end
end
```

---

## 🛸 Custom Telemetry Collectors

### Comprehensive Metrics Collector

ThrottleMachines keeps no registry of limiters: they are cheap frozen values over shared storage. Watch the ones you care about. Circuits do have a registry: `BreakerMachines::Registry.instance`.

```ruby
class ThrottleTelemetry
  NS = ThrottleMachines::NS_PER_SECOND
  MS = 1_000_000

  # The limiters worth watching, rebuilt on demand (same key, same state)
  WATCHED = {
    "api" => -> { ThrottleMachines.limiter("api", limit: 1000, period: 60 * NS) },
    "login" => -> { ThrottleMachines.limiter("login", limit: 5, period: 300 * NS) }
  }.freeze

  class << self
    def collect_metrics
      {
        limiters: collect_limiter_metrics,
        breakers: collect_breaker_metrics,
        storage: collect_storage_metrics,
        system: collect_system_metrics
      }
    end

    private

    def collect_limiter_metrics
      WATCHED.map do |name, build|
        snapshot = build.call.to_h  # key, limit, period (ns), algorithm, remaining, retry_after (ns)
        used = snapshot[:limit] - snapshot[:remaining]

        snapshot.merge(
          name: name,
          usage_percentage: (used * 100.0 / snapshot[:limit]).round(2)
        )
      end
    end

    def collect_breaker_metrics
      BreakerMachines::Registry.instance.all_circuits.map do |breaker|
        stats = breaker.stats
        {
          name: breaker.name,
          state: breaker.state,
          failure_count: stats.failure_count,
          last_failure_at: stats.last_failure_at,  # ns, on the circuit's clock
          opened_at: stats.opened_at,              # ns, nil unless open
          retry_after: breaker.retry_after         # ns until a probe may run
        }
      end
    end

    def collect_storage_metrics
      storage = ThrottleMachines.storage
      type = storage.class.name.split("::").last.downcase

      started = ThrottleMachines.monotonic_time
      healthy = storage.healthy?
      latency = ThrottleMachines.monotonic_time - started

      {
        type: type,
        status: healthy ? "healthy" : "unhealthy",
        latency_ms: latency / MS
      }
    end

    def collect_system_metrics
      summary = BreakerMachines::Registry.instance.stats_summary
      {
        watched_limiters: WATCHED.size,
        total_breakers: summary[:total],
        breakers_by_state: summary[:by_state],
        version: ThrottleMachines::VERSION
      }
    end
  end
end
```

### Real-time Dashboard Data
```ruby
class TelemetryDashboard
  def self.snapshot
    {
      timestamp: Time.current.iso8601,
      traffic: current_traffic_stats,
      alerts: active_alerts,
      top_limited: top_limited_endpoints,
      system_health: system_health_score
    }
  end

  private

  def self.current_traffic_stats
    {
      requests_per_minute: redis.get("stats:rpm").to_i,
      throttled_per_minute: redis.get("stats:throttled_rpm").to_i,
      throttle_rate: calculate_throttle_rate,
      unique_ips: redis.scard("stats:unique_ips:#{current_minute}")
    }
  end

  def self.active_alerts
    alerts = []

    # Check for high throttle rates
    if calculate_throttle_rate > 10
      alerts << {
        level: "warning",
        message: "High throttle rate detected",
        value: "#{calculate_throttle_rate}%"
      }
    end

    # Check for open circuits
    open_circuits = BreakerMachines::Registry.instance.all_circuits.select(&:open?)
    if open_circuits.any?
      alerts << {
        level: "critical",
        message: "#{open_circuits.count} circuit(s) open",
        circuits: open_circuits.map(&:name)
      }
    end

    alerts
  end

  def self.top_limited_endpoints
    # Get from Redis sorted set
    redis.zrevrange("stats:throttled_endpoints", 0, 4, with_scores: true)
      .map { |endpoint, count| { endpoint: endpoint, count: count.to_i } }
  end

  def self.system_health_score
    score = 100

    # Deduct for high throttle rate
    throttle_rate = calculate_throttle_rate
    score -= [throttle_rate, 30].min

    # Deduct for open circuits
    open_circuits = BreakerMachines::Registry.instance.all_circuits.count(&:open?)
    score -= (open_circuits * 10)

    # Deduct for storage issues (healthy? answers false, it doesn't raise)
    score -= 20 unless ThrottleMachines.storage.healthy?

    [score, 0].max  # Never go below 0
  end

  def self.calculate_throttle_rate
    rpm = redis.get("stats:rpm").to_f
    throttled = redis.get("stats:throttled_rpm").to_f

    return 0 if rpm.zero?
    ((throttled / rpm) * 100).round(2)
  end

  def self.redis
    @redis ||= Redis.new
  end

  def self.current_minute
    Time.current.strftime("%Y%m%d%H%M")
  end
end
```

---

## 📈 Performance Monitoring

### Request Performance Tracking
```ruby
class PerformanceMonitor
  NS = ThrottleMachines::NS_PER_SECOND
  MS = 1_000_000
  SLOW = 1 * NS

  def self.track_request(name, &block)
    start_time = ThrottleMachines.monotonic_time  # Integer ns
    memory_before = current_memory_usage

    begin
      result = yield

      track_success(name, start_time, memory_before)
      result
    rescue => e
      track_failure(name, start_time, memory_before, e)
      raise
    end
  end

  private

  def self.track_success(name, start_time, memory_before)
    duration = ThrottleMachines.monotonic_time - start_time
    memory_delta = current_memory_usage - memory_before

    StatsD.histogram("request.duration", duration / MS, tags: ["endpoint:#{name}"])
    StatsD.histogram("request.memory_delta", memory_delta, tags: ["endpoint:#{name}"])

    # Log slow requests
    if duration > SLOW
      Rails.logger.warn "Slow request detected: #{name} took #{duration / MS}ms"
    end
  end

  def self.track_failure(name, start_time, memory_before, error)
    duration = ThrottleMachines.monotonic_time - start_time

    StatsD.increment("request.errors", tags: ["endpoint:#{name}", "error:#{error.class}"])

    Rails.logger.error "Request failed: #{name} - #{error.message} (#{duration / MS}ms)"
  end

  def self.current_memory_usage
    # Get current process memory usage in MB
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  end
end

# Usage in controllers
class ApplicationController < ActionController::Base
  around_action :monitor_performance

  private

  def monitor_performance
    PerformanceMonitor.track_request(monitoring_name) do
      yield
    end
  end

  def monitoring_name
    "#{controller_name}##{action_name}"
  end
end
```

---

## 🎯 Alerting & Anomaly Detection

### Smart Alert System
```ruby
class ThrottleAnomalyDetector
  def self.check_for_anomalies
    anomalies = []

    # Sudden spike in throttled requests
    if spike_detected?(:throttled_requests)
      anomalies << {
        type: "throttle_spike",
        severity: "high",
        message: "Throttled requests increased by #{spike_percentage(:throttled_requests)}%"
      }
    end

    # Unusual geographic patterns
    if unusual_geographic_activity?
      anomalies << {
        type: "geographic_anomaly",
        severity: "medium",
        message: "Unusual traffic from #{unusual_regions.join(', ')}"
      }
    end

    # Circuit breaker cascade
    if circuit_cascade_risk?
      anomalies << {
        type: "cascade_risk",
        severity: "critical",
        message: "Multiple circuits approaching failure threshold"
      }
    end

    # Process anomalies
    anomalies.each { |anomaly| process_anomaly(anomaly) }
  end

  private

  def self.spike_detected?(metric)
    current = current_value(metric)
    baseline = baseline_value(metric)

    return false if baseline.zero?

    change_ratio = (current - baseline).to_f / baseline
    change_ratio > 0.5  # 50% increase
  end

  def self.spike_percentage(metric)
    current = current_value(metric)
    baseline = baseline_value(metric)

    return 0 if baseline.zero?

    (((current - baseline).to_f / baseline) * 100).round
  end

  def self.unusual_geographic_activity?
    current_regions = redis.smembers("geo:current_hour")
    typical_regions = redis.smembers("geo:typical")

    new_regions = current_regions - typical_regions
    new_regions.size > 3  # More than 3 new regions
  end

  def self.circuit_cascade_risk?
    at_risk = BreakerMachines::Registry.instance.all_circuits.count do |breaker|
      threshold = breaker.policy.threshold.count
      threshold && breaker.stats.failure_count > (threshold * 0.7)
    end

    at_risk >= 3  # 3 or more circuits near failure
  end

  def self.process_anomaly(anomaly)
    # Log it
    Rails.logger.warn "Anomaly detected: #{anomaly.to_json}"

    # Send appropriate alerts
    case anomaly[:severity]
    when "critical"
      PagerDuty.trigger("Critical anomaly", anomaly)
      Slack.alert("#ops-critical", format_anomaly(anomaly))
    when "high"
      Slack.alert("#ops-alerts", format_anomaly(anomaly))
    when "medium"
      Slack.notify("#ops-monitoring", format_anomaly(anomaly))
    end

    # Store for analysis
    redis.lpush("anomalies:#{Date.today}", anomaly.to_json)
    redis.expire("anomalies:#{Date.today}", 7 * 86_400)  # Redis EXPIRE speaks seconds
  end

  def self.format_anomaly(anomaly)
    emoji = case anomaly[:severity]
            when "critical" then "🚨"
            when "high" then "⚠️"
            when "medium" then "📊"
            end

    "#{emoji} #{anomaly[:message]}"
  end
end

# Run anomaly detection periodically
class AnomalyDetectionJob < ApplicationJob
  queue_as :monitoring

  def perform
    ThrottleAnomalyDetector.check_for_anomalies
  end
end
```

---

## 📊 Grafana Dashboard Configuration

### Example Dashboard JSON
```json
{
  "dashboard": {
    "title": "ThrottleMachines Telemetry",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [
          {
            "target": "stats.gauges.requests_per_minute"
          },
          {
            "target": "stats.gauges.throttled_per_minute"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Circuit Breaker Status",
        "targets": [
          {
            "target": "stats.gauges.circuits.*.state"
          }
        ],
        "type": "stat"
      },
      {
        "title": "Top Throttled Endpoints",
        "targets": [
          {
            "target": "stats.counters.throttle.endpoint.*"
          }
        ],
        "type": "table"
      },
      {
        "title": "Storage Latency",
        "targets": [
          {
            "target": "stats.timers.storage.redis.latency"
          }
        ],
        "type": "graph"
      }
    ]
  }
}
```

---

## 🔧 Custom Metrics Exporters

### Prometheus Exporter
```ruby
# lib/throttle_machines/prometheus_exporter.rb
require 'prometheus/client'
require 'prometheus/client/formats/text'

class ThrottleMachines::PrometheusExporter
  STATE_VALUES = { closed: 0, open: 1, half_open: 2 }.freeze

  def initialize
    @registry = Prometheus::Client.registry
    setup_metrics
    subscribe
  end

  def call(_env)
    update_metrics
    [200, {"content-type" => "text/plain"}, [Prometheus::Client::Formats::Text.marshal(@registry)]]
  end

  private

  def setup_metrics
    @request_counter = @registry.counter(
      :throttle_requests_total,
      docstring: "Total number of throttle checks",
      labels: [:result]
    )

    @circuit_state = @registry.gauge(
      :circuit_breaker_state,
      docstring: "Circuit breaker state (0=closed, 1=open, 2=half-open)",
      labels: [:name]
    )

    @storage_latency = @registry.histogram(
      :storage_latency_seconds,
      docstring: "Storage health check latency",
      labels: [:operation]
    )
  end

  # Count decisions as they happen, instead of probing limiters on scrape
  def subscribe
    ActiveSupport::Notifications.subscribe(/\Arate_limit\.(allowed|throttled)\.throttle_machines\z/) do |name|
      result = name.start_with?("rate_limit.allowed") ? "allowed" : "throttled"
      @request_counter.increment(labels: { result: result })
    end
  end

  def update_metrics
    # Update circuit breaker metrics
    BreakerMachines::Registry.instance.all_circuits.each do |breaker|
      @circuit_state.set(STATE_VALUES.fetch(breaker.state), labels: { name: breaker.name })
    end

    # Prometheus wants seconds: convert at the export boundary only
    started = ThrottleMachines.monotonic_time
    ThrottleMachines.storage.healthy?
    elapsed = ThrottleMachines.monotonic_time - started
    @storage_latency.observe(elapsed.fdiv(ThrottleMachines::NS_PER_SECOND), labels: { operation: "health" })
  end
end

# Mount in config.ru
map "/metrics" do
  run ThrottleMachines::PrometheusExporter.new
end
```

---

## 🚀 Mission Critical Monitoring

### Health Check Endpoint
```ruby
class HealthCheckController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    health = {
      status: overall_status,
      timestamp: Time.current.iso8601,
      components: {
        rate_limiting: check_rate_limiting,
        circuit_breakers: check_circuit_breakers,
        storage: check_storage,
        performance: check_performance
      }
    }

    status_code = health[:status] == "healthy" ? 200 : 503
    render json: health, status: status_code
  end

  private

  def overall_status
    components = [
      check_rate_limiting[:status],
      check_circuit_breakers[:status],
      check_storage[:status],
      check_performance[:status]
    ]

    if components.all? { |s| s == "healthy" }
      "healthy"
    elsif components.any? { |s| s == "critical" }
      "critical"
    else
      "degraded"
    end
  end

  def check_rate_limiting
    # Test creating a limiter
    test_limiter = ThrottleMachines.limiter("health_check", limit: 1, period: 1 * ThrottleMachines::NS_PER_SECOND)
    test_limiter.allow?

    { status: "healthy", message: "Rate limiting operational" }
  rescue => e
    { status: "critical", message: "Rate limiting failed", error: e.message }
  end

  def check_circuit_breakers
    open_circuits = BreakerMachines::Registry.instance.all_circuits.select(&:open?).map(&:name)

    if open_circuits.empty?
      { status: "healthy", message: "All circuits closed" }
    elsif open_circuits.size < 3
      { status: "degraded", message: "#{open_circuits.size} circuits open", circuits: open_circuits }
    else
      { status: "critical", message: "Multiple circuits open", circuits: open_circuits }
    end
  end

  def check_storage
    ms = 1_000_000
    start = ThrottleMachines.monotonic_time
    healthy = ThrottleMachines.storage.healthy?
    latency = ThrottleMachines.monotonic_time - start  # Integer ns

    if !healthy
      { status: "critical", message: "Storage unavailable" }
    elsif latency < 10 * ms
      { status: "healthy", message: "Storage responsive", latency_ms: latency / ms }
    elsif latency < 50 * ms
      { status: "degraded", message: "Storage slow", latency_ms: latency / ms }
    else
      { status: "critical", message: "Storage very slow", latency_ms: latency / ms }
    end
  rescue => e
    { status: "critical", message: "Storage unavailable", error: e.message }
  end

  def check_performance
    # Check recent performance metrics
    avg_response_time = Rails.cache.fetch("metrics:avg_response_time", expires_in: 60) do
      calculate_average_response_time
    end

    if avg_response_time < 100
      { status: "healthy", message: "Performance optimal", avg_ms: avg_response_time }
    elsif avg_response_time < 500
      { status: "degraded", message: "Performance degraded", avg_ms: avg_response_time }
    else
      { status: "critical", message: "Performance critical", avg_ms: avg_response_time }
    end
  end

  def calculate_average_response_time
    # Implement based on your metrics collection
    rand(50..150)  # Placeholder
  end
end
```

---

## 🚀 Next Missions

- **[🎮 Command Examples](COMMAND_EXAMPLES.md)** - Real-world monitoring scenarios

---

**"In space, telemetry isn't just data - it's the difference between coming home and becoming cosmic dust."**

*— Mission Control Operator's Handbook*
