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
```ruby
# config/initializers/throttle_telemetry.rb

# Subscribe to all ThrottleMachines events
ActiveSupport::Notifications.subscribe(/throttle_machines/) do |name, start, finish, id, payload|
  duration = (finish - start) * 1000  # Convert to milliseconds
  
  case name
  when "throttle.throttle_machines"
    Rails.logger.info "⚡ Rate limit checked: #{payload[:key]} - " \
                     "Allowed: #{payload[:allowed]} - Duration: #{duration.round(2)}ms"
    
    # Send to metrics system
    StatsD.increment("throttle.checks", tags: ["allowed:#{payload[:allowed]}"])
    StatsD.histogram("throttle.check_duration", duration)
    
  when "circuit_open.throttle_machines"
    Rails.logger.warn "🛡️ Circuit breaker opened: #{payload[:name]} - " \
                     "Failures: #{payload[:failure_count]}"
    
    # Alert operations team
    PagerDuty.trigger(
      "Circuit breaker #{payload[:name]} is open",
      details: payload
    )
    
  when "circuit_reset.throttle_machines"
    Rails.logger.info "✅ Circuit breaker reset: #{payload[:name]}"
    
    StatsD.event("Circuit breaker recovered", 
                "#{payload[:name]} is operational again")
  end
end

# Rack middleware telemetry
ActiveSupport::Notifications.subscribe(/rack_attack/) do |name, start, finish, id, payload|
  request = payload[:request]
  
  case name
  when "throttle.rack_attack"
    StatsD.increment("rack.throttled", 
      tags: ["path:#{request.path}", "ip:#{request.ip}"])
    
  when "blocklist.rack_attack"
    Rails.logger.error "🚫 Blocked request from #{request.ip} to #{request.path}"
    SecurityAlert.notify("Blocked IP", ip: request.ip, path: request.path)
    
  when "safelist.rack_attack"
    StatsD.increment("rack.safelisted")
    
  when "track.rack_attack"
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
```ruby
class ThrottleTelemetry
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
      # Collect metrics for all active limiters
      limiters = ThrottleMachines.limiters  # Hypothetical method
      
      limiters.map do |name, limiter|
        {
          name: name,
          limit: limiter.limit,
          period: limiter.period,
          algorithm: limiter.algorithm,
          current_usage: limiter.current_count,
          usage_percentage: (limiter.current_count.to_f / limiter.limit * 100).round(2)
        }
      end
    end
    
    def collect_breaker_metrics
      breakers = ThrottleMachines.breakers  # Hypothetical method
      
      breakers.map do |name, breaker|
        {
          name: name,
          state: breaker.status_name,
          failure_count: breaker.stats.failure_count,
          last_failure: breaker.last_failure_time,
          opens_count: breaker.total_opens,
          uptime_percentage: calculate_uptime(breaker)
        }
      end
    end
    
    def collect_storage_metrics
      storage = ThrottleMachines.configuration.storage
      
      if storage.is_a?(ThrottleMachines::Storage::Redis)
        measure_redis_health(storage)
      else
        { type: "memory", status: "healthy" }
      end
    end
    
    def measure_redis_health(storage)
      start = Time.current
      storage.with_redis { |r| r.ping }
      latency = (Time.current - start) * 1000
      
      {
        type: "redis",
        status: "healthy",
        latency_ms: latency.round(2),
        pool_size: storage.pool.size,
        pool_available: storage.pool.available
      }
    rescue => e
      {
        type: "redis",
        status: "unhealthy",
        error: e.message
      }
    end
    
    def calculate_uptime(breaker)
      total_time = Time.current - breaker.created_at
      open_time = breaker.time_spent_open
      ((total_time - open_time) / total_time * 100).round(2)
    end
    
    def collect_system_metrics
      {
        total_limiters: ThrottleMachines.limiters.count,
        total_breakers: ThrottleMachines.breakers.count,
        memory_usage_mb: (ObjectSpace.memsize_of_all(ThrottleMachines) / 1024.0 / 1024.0).round(2),
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
    open_circuits = ThrottleMachines.breakers.select { |_, b| b.status_name == :open }
    if open_circuits.any?
      alerts << {
        level: "critical",
        message: "#{open_circuits.count} circuit(s) open",
        circuits: open_circuits.keys
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
    open_circuits = ThrottleMachines.breakers.count { |_, b| b.status_name == :open }
    score -= (open_circuits * 10)
    
    # Deduct for storage issues
    begin
      ThrottleMachines.configuration.storage.healthy?
    rescue
      score -= 20
    end
    
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
  def self.track_request(name, &block)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    memory_delta = current_memory_usage - memory_before
    
    StatsD.histogram("request.duration", duration * 1000, tags: ["endpoint:#{name}"])
    StatsD.histogram("request.memory_delta", memory_delta, tags: ["endpoint:#{name}"])
    
    # Log slow requests
    if duration > 1.0  # 1 second
      Rails.logger.warn "Slow request detected: #{name} took #{duration.round(3)}s"
    end
  end
  
  def self.track_failure(name, start_time, memory_before, error)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    
    StatsD.increment("request.errors", tags: ["endpoint:#{name}", "error:#{error.class}"])
    
    Rails.logger.error "Request failed: #{name} - #{error.message} (#{duration.round(3)}s)"
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
    at_risk = ThrottleMachines.breakers.count do |_, breaker|
      breaker.failure_count > (breaker.threshold * 0.7)
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
    redis.expire("anomalies:#{Date.today}", 7.days)
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

class ThrottleMachines::PrometheusExporter
  def initialize
    @registry = Prometheus::Client.registry
    setup_metrics
  end
  
  def call(env)
    update_metrics
    
    if env["PATH_INFO"] == "/metrics"
      [200, {"content-type" => "text/plain"}, [Prometheus::Client::Formats::Text.marshal(@registry)]]
    else
      [404, {"content-type" => "text/plain"}, ["Not Found"]]
    end
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
      docstring: "Storage operation latency",
      labels: [:operation]
    )
  end
  
  def update_metrics
    # Update throttle metrics
    ThrottleMachines.limiters.each do |name, limiter|
      allowed = limiter.allowed?
      @request_counter.increment(labels: { result: allowed ? "allowed" : "throttled" })
    end
    
    # Update circuit breaker metrics
    ThrottleMachines.breakers.each do |name, breaker|
      state_value = case breaker.status_name
                    when :closed then 0
                    when :open then 1
                    when :half_open then 2
                    end
      @circuit_state.set(state_value, labels: { name: name })
    end
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
    test_limiter = ThrottleMachines.limiter("health_check", limit: 1, period: 1)
    test_limiter.allowed?
    
    { status: "healthy", message: "Rate limiting operational" }
  rescue => e
    { status: "critical", message: "Rate limiting failed", error: e.message }
  end
  
  def check_circuit_breakers
    open_circuits = ThrottleMachines.breakers.select { |_, b| b.status_name == :open }
    
    if open_circuits.empty?
      { status: "healthy", message: "All circuits closed" }
    elsif open_circuits.size < 3
      { status: "degraded", message: "#{open_circuits.size} circuits open", circuits: open_circuits.keys }
    else
      { status: "critical", message: "Multiple circuits open", circuits: open_circuits.keys }
    end
  end
  
  def check_storage
    start = Time.current
    ThrottleMachines.configuration.storage.healthy?
    latency = (Time.current - start) * 1000
    
    if latency < 10
      { status: "healthy", message: "Storage responsive", latency_ms: latency.round(2) }
    elsif latency < 50
      { status: "degraded", message: "Storage slow", latency_ms: latency.round(2) }
    else
      { status: "critical", message: "Storage very slow", latency_ms: latency.round(2) }
    end
  rescue => e
    { status: "critical", message: "Storage unavailable", error: e.message }
  end
  
  def check_performance
    # Check recent performance metrics
    avg_response_time = Rails.cache.fetch("metrics:avg_response_time", expires_in: 1.minute) do
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
