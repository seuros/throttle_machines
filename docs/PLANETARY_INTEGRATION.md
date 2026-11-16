# 🌍 Planetary Integration

> **Rails & Rack Middleware** - Establishing diplomatic relations with planet Rails and the Rack Federation

When your spacecraft (gem) arrives at a new planet (Rails app), you need proper docking procedures. This guide covers integrating ThrottleMachines with Rails controllers and Rack middleware.

---

## 🚀 Rails Controller Integration

`ThrottleMachines::ControllerHelpers` is the docking clamp: `throttle!`,
`with_throttle`, `rate_limited?` and `rate_limit_remaining`. Every `period:` is
Integer nanoseconds; the 429 body and the `Retry-After` header report the wait
in whole seconds, rounded up. Without an explicit key, ships are identified as
`user:<id>` (when `current_user` answers `id`) or `ip:<remote_ip>`.

### Basic Docking Procedures
```ruby
NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000

class ApiController < ApplicationController
  include ThrottleMachines::ControllerHelpers

  # Establish rate limiting for the entire space station
  before_action do
    # Identify ships by their registration (user ID) or origin (IP)
    throttle!("api_rate_limit:#{current_user&.id || request.remote_ip}",
      limit: 1000,
      period: 3600 * NS,  # 1000 requests per hour
      algorithm: :gcra)
  end
end
```

### Advanced Planetary Defense System
```ruby
class SpaceStationController < ApplicationController
  include ThrottleMachines::ControllerHelpers

  # Different limits for different ship classes
  before_action only: [:index, :show] do
    throttle!("standard_docking:#{identify_ship}",
      limit: 100,
      period: 300 * NS)  # 100 requests per 5 minutes
  end

  before_action only: [:create, :update] do
    throttle!("cargo_loading:#{current_user.id}",
      limit: 10,
      period: 60 * NS,  # 10 heavy operations per minute
      algorithm: :token_bucket)
  end

  before_action only: [:emergency_evacuation] do
    throttle!("emergency:#{request.remote_ip}",
      limit: 1,
      period: 300 * NS,  # 1 emergency call per 5 minutes
      algorithm: :fixed_window)
  end

  # Actions
  def index
    render json: { ships: Ship.docked }
  end

  def create
    ship = Ship.create!(ship_params)
    render json: { docking_bay: ship.bay_number }
  end

  def emergency_evacuation
    EvacuationProtocol.execute!
    render json: { status: "Evacuation initiated" }
  end

  private

  def identify_ship
    # Authenticated ships get identified by captain
    # Unknown ships identified by origin coordinates
    current_user&.id || "anon:#{request.remote_ip}"
  end
end
```

A `throttle!` that renders the 429 halts the `before_action` chain, so the
action never runs.

### Conditional Planetary Defenses
```ruby
class ConditionalDefenseController < ApplicationController
  include ThrottleMachines::ControllerHelpers

  # Only throttle suspicious activity
  before_action if: :suspicious_activity? do
    throttle!("suspicious_scanner:#{request.remote_ip}", limit: 5, period: 60 * NS)
  end

  # Different limits for different user ranks
  before_action do
    throttle!("ranked_access:#{current_user.id}",
      limit: rate_limit_for_rank,
      period: 60 * NS,
      algorithm: :gcra)
  end

  private

  def suspicious_activity?
    # Detect scanning patterns
    request.user_agent =~ /bot|scanner|crawler/i ||
    request.path =~ /\.(php|asp|env)/ ||
    params[:test]&.include?("<script")
  end

  def rate_limit_for_rank
    case current_user&.rank
    when "Admiral"
      10000  # Nearly unlimited
    when "Captain"
      1000   # High limit
    when "Lieutenant"
      100    # Standard limit
    else
      10     # Restricted access
    end
  end
end
```

---

## 📡 Rack Middleware - Universal Translator

### Basic Federation Protocol
```ruby
# config/application.rb (Rails)
require 'throttle_machines/rack_middleware'

module YourSpaceStation
  class Application < Rails::Application
    # Universal translator for all incoming transmissions
    config.middleware.use ThrottleMachines::RackMiddleware
  end
end
```

### Complete Defensive Grid Configuration
```ruby
# config/initializers/throttle_machines.rb

NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000

# Configure your defensive systems
ThrottleMachines.configure do |config|
  # Default to smooth traffic patterns
  config.default_algorithm = :gcra
end

# Quantum storage for distributed fleets (a client or a ConnectionPool)
redis_pool = ConnectionPool.new(size: 10) { Redis.new }
ThrottleMachines.storage = ThrottleMachines::Storage::Redis.new(redis: redis_pool)

# Defensive Perimeter Configuration
ThrottleMachines::RackMiddleware.configure do |grid|

  # === Primary Defense Layer ===

  # Overall station defense - smooth traffic distribution
  grid.throttle("station_defense",
    limit: 5000,
    period: 300 * NS,  # 5000 requests per 5 minutes
    algorithm: :gcra
  ) do |req|
    req.ip  # Track by origin coordinates
  end

  # === Dock-Specific Defenses ===

  # API dock - higher limits, token bucket for bursts
  grid.throttle("api_dock",
    limit: 100,
    period: 60 * NS,
    algorithm: :token_bucket
  ) do |req|
    req.path.start_with?("/api") && req.ip
  end

  # Authentication airlock - strict limits
  grid.throttle("auth_airlock",
    limit: 5,
    period: 300 * NS,  # 5 attempts per 5 minutes
    algorithm: :fixed_window
  ) do |req|
    if req.path == "/login" && req.post?
      # Track by IP and username combo
      username = req.params["username"]
      username ? "#{req.ip}:#{username}" : req.ip
    end
  end

  # === Hostile Detection Systems ===

  # Block known hostile territories
  hostile_sectors = %w[
    192.168.1.666
    10.0.0.13
  ]

  grid.blocklist("hostile_sectors") do |req|
    hostile_sectors.include?(req.ip)
  end

  # Block suspicious probe patterns
  grid.blocklist("probe_detection") do |req|
    # WordPress admin probes
    req.path.include?("wp-admin") ||
    # Environment file scans
    req.path.include?(".env") ||
    # SQL injection attempts
    req.query_string.match?(/union.*select/i)
  end

  # === Safe Passage Permits ===

  # Always allow federation ships
  grid.safelist("federation_vessels") do |req|
    req.ip == "127.0.0.1" ||
    req.ip == "::1" ||
    req.env["HTTP_X_FEDERATION_KEY"] == ENV["FEDERATION_SECRET"]
  end

  # VIP bypass for premium members
  grid.safelist("vip_bypass") do |req|
    # Check for valid VIP token
    token = req.env["HTTP_AUTHORIZATION"]
    token && VIPToken.valid?(token)
  end

  # === Tracking Systems ===

  # Monitor suspicious activity without blocking
  grid.track("scanner_detection") do |req|
    # Track but don't block potential scanners
    req.user_agent =~ /scanner|bot|spider/i ? req.ip : nil
  end

  # === Fail2Ban Shield Protocols ===

  # Ban after too many 404s (probe detection). Keep the filter: you feed it.
  PROBE_SHIELD = grid.fail2ban("probe_shield",
    maxretry: 20,          # 20 404s
    findtime: 60 * NS,     # within 1 minute
    bantime: 1800 * NS     # ban for 30 minutes
  ) do |req|
    req.ip
  end

  # In your ApplicationController:
  # after_action :record_not_found
  # def record_not_found
  #   PROBE_SHIELD.count(request) { response.status == 404 }
  # end
  #
  # A banned ship's match_data carries time_until_unban (Integer ns).

  # === Response Customization ===

  # Custom responses for different scenarios.
  # match_data[:retry_after] is Integer nanoseconds; the wire speaks whole seconds.
  grid.throttled_responder = lambda do |request|
    match_data = request.env['rack.attack.match_data']
    wait = match_data[:retry_after].ceildiv(NS)
    [
      429,
      {
        "content-type" => "application/json",
        "retry-after" => wait.to_s
      },
      [{
        error: "Transmission rate exceeded",
        message: "Your ship is transmitting too rapidly",
        retry_after: wait,
        limit: match_data[:limit]
      }.to_json]
    ]
  end

  grid.blocklisted_responder = lambda do |request|
    [
      403,
      {"content-type" => "application/json"},
      [{
        error: "Access Denied",
        message: "Your vessel has been denied docking privileges",
        reason: "Security Protocol Violation"
      }.to_json]
    ]
  end
end
```

---

## 🛸 Integration Patterns

### Pattern 1: Multi-Tenant Space Station
```ruby
class MultiTenantDefense
  def self.configure!
    ThrottleMachines::RackMiddleware.configure do |grid|
      # Each tenant gets their own limits
      grid.throttle("tenant_limits",
        limit: ->(req) { tenant_limit(req) },
        period: 3600 * NS,
        algorithm: :gcra
      ) do |req|
        tenant_id = extract_tenant_id(req)
        tenant_id ? "tenant:#{tenant_id}" : nil
      end
    end
  end

  private

  def self.extract_tenant_id(request)
    # From subdomain: acme.example.com
    request.host.split('.').first ||
    # From header: X-Tenant-ID
    request.env["HTTP_X_TENANT_ID"] ||
    # From JWT token
    extract_from_jwt(request)
  end

  def self.tenant_limit(request)
    tenant_id = extract_tenant_id(request)
    return 100 unless tenant_id  # Default limit

    # Look up tenant's plan
    tenant = Tenant.find_by(identifier: tenant_id)
    case tenant&.plan
    when "enterprise"
      10000
    when "business"
      5000
    when "starter"
      1000
    else
      100
    end
  end
end
```

### Pattern 2: Geographic Defense Grid
```ruby
class GeographicDefense
  def self.configure!
    ThrottleMachines::RackMiddleware.configure do |grid|
      # Different limits by region
      grid.throttle("regional_limits",
        limit: ->(req) { limit_for_region(req) },
        period: 60 * NS,
        algorithm: :gcra
      ) do |req|
        "#{region_from_ip(req.ip)}:#{req.ip}"
      end

      # Block specific regions during maintenance
      grid.blocklist("regional_maintenance") do |req|
        region = region_from_ip(req.ip)
        MaintenanceWindow.active_for?(region)
      end
    end
  end

  private

  def self.region_from_ip(ip)
    # Use GeoIP lookup
    GeoIP.new.country(ip).continent_code
  rescue
    "unknown"
  end

  def self.limit_for_region(request)
    region = region_from_ip(request.ip)

    case region
    when "NA", "EU"  # Primary markets
      1000
    when "AS"        # Growing market
      500
    else             # Emerging markets
      100
    end
  end
end
```

### Pattern 3: API Version Management
```ruby
class APIVersionDefense
  def self.configure!
    ThrottleMachines::RackMiddleware.configure do |grid|
      # Legacy API - strict limits to encourage upgrade
      grid.throttle("api_v1_limits",
        limit: 100,
        period: 3600 * NS,
        algorithm: :fixed_window
      ) do |req|
        req.path.start_with?("/api/v1") && extract_api_key(req)
      end

      # Current API - generous limits
      grid.throttle("api_v2_limits",
        limit: 1000,
        period: 3600 * NS,
        algorithm: :gcra
      ) do |req|
        req.path.start_with?("/api/v2") && extract_api_key(req)
      end

      # Beta API - moderate limits with monitoring
      grid.throttle("api_v3_beta",
        limit: 500,
        period: 3600 * NS,
        algorithm: :token_bucket
      ) do |req|
        if req.path.start_with?("/api/v3-beta")
          api_key = extract_api_key(req)
          # Track beta usage
          BetaUsageTracker.record(api_key) if api_key
          api_key
        end
      end
    end
  end

  private

  def self.extract_api_key(request)
    # From header
    request.env["HTTP_X_API_KEY"] ||
    # From query params
    request.params["api_key"] ||
    # From Authorization header
    extract_from_bearer_token(request)
  end
end
```

---

## 🔧 Rails-Specific Enhancements

There are no Cable or Job mixins: limiters are plain objects, so dock them
wherever a request crosses the airlock.

### ActionCable Integration
```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    NS = ThrottleMachines::NS_PER_SECOND

    identified_by :current_user

    def connect
      # Ships with 10 failed handshakes in 5 minutes wait at the airlock
      reject_unauthorized_connection unless auth_failures.allow?

      # Throttle WebSocket connections: 5 per minute per origin
      ThrottleMachines.limit("cable:connect:#{request.ip}", limit: 5, period: 60 * NS)

      self.current_user = find_verified_user
      logger.add_tags 'ActionCable', current_user.id
    rescue ThrottleMachines::ThrottledError
      reject_unauthorized_connection
    end

    private

    def auth_failures
      ThrottleMachines.limiter("cable:auth:#{request.ip}", limit: 10, period: 300 * NS)
    end

    def find_verified_user
      if verified_user = User.find_by(id: cookies.signed[:user_id])
        verified_user
      else
        # Count the failed authentication attempt (raises ThrottledError at the limit)
        auth_failures.throttle!
        reject_unauthorized_connection
      end
    end
  end
end
```

### ActiveJob Integration
```ruby
class ApplicationJob < ActiveJob::Base
  NS = ThrottleMachines::NS_PER_SECOND

  # Throttle job execution rate: [limit, period ns, algorithm]
  class_attribute :throttle_rate, default: [1000, 60 * NS, :fixed_window]

  around_perform do |job, block|
    limit, period, algorithm = job.throttle_rate
    ThrottleMachines.limit("jobs:#{job.class.name}",
      limit: limit, period: period, algorithm: algorithm, &block)
  rescue ThrottleMachines::ThrottledError => e
    # ActiveJob schedules in seconds: round the nanosecond wait up
    job.retry_job(wait: e.retry_after.ceildiv(NS))
  end

  # Custom throttling for specific job classes
  class HighPriorityJob < ApplicationJob
    self.throttle_rate = [10000, 60 * NS, :gcra]
  end

  class BatchProcessingJob < ApplicationJob
    self.throttle_rate = [10, 300 * NS, :token_bucket]
  end
end
```

---

## 📊 Monitoring Integration Health

```ruby
# app/models/throttle_health_check.rb
class ThrottleHealthCheck
  def self.status
    {
      middleware_active: middleware_active?,
      storage_healthy: storage_healthy?,
      current_limits: current_limit_status,
      performance_metrics: performance_metrics
    }
  end

  private

  def self.middleware_active?
    Rails.application.middleware.include?(ThrottleMachines::RackMiddleware)
  end

  def self.storage_healthy?
    ThrottleMachines.storage.healthy?
  end

  def self.current_limit_status
    ThrottleMachines::RackMiddleware.throttles.map do |name, throttle|
      {
        name: name,
        limit: throttle.limit,
        period: throttle.period,  # Integer ns (or a callable answering them)
        algorithm: throttle.algorithm
      }
    end
  end

  def self.performance_metrics
    {
      avg_check_time_ns: nil,   # Would need actual measurement
      storage_latency_ns: measure_storage_latency,
      memory_usage: "2.1MB"     # Would need actual measurement
    }
  end

  # Integer nanoseconds for one non-consuming check
  def self.measure_storage_latency
    start = ThrottleMachines.monotonic_time
    ThrottleMachines.limiter("latency_test", limit: 1, period: ThrottleMachines::NS_PER_SECOND).allow?
    ThrottleMachines.monotonic_time - start
  end
end
```

---

## 🚀 Next Missions

- **[🔬 Space Lab](SPACE_LAB.md)** - Testing your integrations
- **[📡 Telemetry](TELEMETRY.md)** - Monitoring planetary defenses
- **[🎮 Command Examples](COMMAND_EXAMPLES.md)** - Battle-tested configurations

---

**"When visiting new worlds, respect their customs while maintaining your ship's integrity."**

*— Diplomatic Corps Integration Manual*
