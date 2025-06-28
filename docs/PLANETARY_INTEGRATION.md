# 🌍 Planetary Integration

> **Rails & Rack Middleware** - Establishing diplomatic relations with planet Rails and the Rack Federation

When your spacecraft (gem) arrives at a new planet (Rails app), you need proper docking procedures. This guide covers integrating ThrottleMachines with Rails controllers and Rack middleware.

---

## 🚀 Rails Controller Integration

### Basic Docking Procedures
```ruby
class ApiController < ApplicationController
  include ThrottleMachines::Rails::Controller
  
  # Establish rate limiting for the entire space station
  throttle :api_rate_limit, 
    limit: 1000, 
    period: 3600,  # 1000 requests per hour
    algorithm: :gcra do |request|
    # Identify ships by their registration (user ID) or origin (IP)
    current_user&.id || request.remote_ip
  end
end
```

### Advanced Planetary Defense System
```ruby
class SpaceStationController < ApplicationController
  include ThrottleMachines::Rails::Controller
  
  # Different limits for different ship classes
  throttle :standard_docking, 
    limit: 100, 
    period: 300,  # 100 requests per 5 minutes
    only: [:index, :show] do |request|
    identify_ship(request)
  end
  
  throttle :cargo_loading,
    limit: 10,
    period: 60,  # 10 heavy operations per minute
    only: [:create, :update],
    algorithm: :token_bucket do |request|
    current_user.id
  end
  
  throttle :emergency_protocol,
    limit: 1,
    period: 300,  # 1 emergency call per 5 minutes
    only: [:emergency_evacuation],
    algorithm: :fixed_window do |request|
    "emergency:#{request.remote_ip}"
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
  
  def identify_ship(request)
    # Authenticated ships get identified by captain
    # Unknown ships identified by origin coordinates
    current_user&.id || "anon:#{request.remote_ip}"
  end
end
```

### Conditional Planetary Defenses
```ruby
class ConditionalDefenseController < ApplicationController
  include ThrottleMachines::Rails::Controller
  
  # Only throttle suspicious activity
  throttle :suspicious_scanner,
    limit: 5,
    period: 60,
    if: :suspicious_activity? do |request|
    request.remote_ip
  end
  
  # Different limits for different user ranks
  throttle :ranked_access,
    limit: ->(request) { rate_limit_for_rank },
    period: 60,
    algorithm: :gcra do |request|
    current_user.id
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

# Configure your defensive systems
ThrottleMachines.configure do |config|
  # Quantum storage for distributed fleets
  redis_pool = ConnectionPool.new(size: 10) { Redis.new }
  config.storage = ThrottleMachines::Storage::Redis.new(pool: redis_pool)
  
  # Default to smooth traffic patterns
  config.default_algorithm = :gcra
end

# Defensive Perimeter Configuration
ThrottleMachines::RackMiddleware.configure do |grid|
  
  # === Primary Defense Layer ===
  
  # Overall station defense - smooth traffic distribution
  grid.throttle("station_defense", 
    limit: 5000, 
    period: 300,  # 5000 requests per 5 minutes
    algorithm: :gcra
  ) do |req|
    req.ip  # Track by origin coordinates
  end
  
  # === Dock-Specific Defenses ===
  
  # API dock - higher limits, token bucket for bursts
  grid.throttle("api_dock",
    limit: 100,
    period: 60,
    algorithm: :token_bucket
  ) do |req|
    req.path.start_with?("/api") && req.ip
  end
  
  # Authentication airlock - strict limits
  grid.throttle("auth_airlock",
    limit: 5,
    period: 300,  # 5 attempts per 5 minutes
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
  
  # Ban after too many 404s (probe detection)
  grid.fail2ban("probe_shield",
    maxretry: 20,     # 20 404s
    findtime: 60,     # within 1 minute
    bantime: 1800     # ban for 30 minutes
  ) do |req|
    req.ip
  end
  
  # In your ApplicationController:
  # after_action :record_not_found
  # def record_not_found
  #   if response.status == 404
  #     ThrottleMachines::RackMiddleware
  #       .fail2ban("probe_shield")
  #       .count(request) { true }
  #   end
  # end
  
  # === Response Customization ===
  
  # Custom responses for different scenarios
  grid.throttled_responder = lambda do |request|
    [
      429,
      {
        "content-type" => "application/json",
        "retry-after" => request.env['rack.attack.match_data'][:retry_after].to_s
      },
      [{
        error: "Transmission rate exceeded",
        message: "Your ship is transmitting too rapidly",
        retry_after: request.env['rack.attack.match_data'][:retry_after],
        limit: request.env['rack.attack.match_data'][:limit]
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
        period: 3600,
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
        period: 60,
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
        period: 3600,
        algorithm: :fixed_window
      ) do |req|
        req.path.start_with?("/api/v1") && extract_api_key(req)
      end
      
      # Current API - generous limits
      grid.throttle("api_v2_limits",
        limit: 1000,
        period: 3600,
        algorithm: :gcra
      ) do |req|
        req.path.start_with?("/api/v2") && extract_api_key(req)
      end
      
      # Beta API - moderate limits with monitoring
      grid.throttle("api_v3_beta",
        limit: 500,
        period: 3600,
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

### ActionCable Integration
```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include ThrottleMachines::Rails::Cable
    
    identified_by :current_user
    
    # Throttle WebSocket connections
    throttle_connections limit: 5, period: 60
    
    def connect
      self.current_user = find_verified_user
      logger.add_tags 'ActionCable', current_user.id
    end
    
    private
    
    def find_verified_user
      if verified_user = User.find_by(id: cookies.signed[:user_id])
        verified_user
      else
        # Throttle failed authentication attempts
        throttle_failed_auth!(request.ip)
        reject_unauthorized_connection
      end
    end
  end
end
```

### ActiveJob Integration
```ruby
class ApplicationJob < ActiveJob::Base
  include ThrottleMachines::Rails::Job
  
  # Throttle job execution rate
  throttle_jobs queue: :default, limit: 1000, period: 60
  
  # Custom throttling for specific job classes
  class HighPriorityJob < ApplicationJob
    throttle_jobs limit: 10000, period: 60, algorithm: :gcra
  end
  
  class BatchProcessingJob < ApplicationJob
    throttle_jobs limit: 10, period: 300, algorithm: :token_bucket
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
    ThrottleMachines.limiter("health_check", limit: 1, period: 1).allowed?
  rescue
    false
  end
  
  def self.current_limit_status
    ThrottleMachines::RackMiddleware.throttles.map do |name, throttle|
      {
        name: name,
        limit: throttle.limit,
        period: throttle.period,
        algorithm: throttle.algorithm
      }
    end
  end
  
  def self.performance_metrics
    {
      avg_check_time: "0.1ms",  # Would need actual measurement
      storage_latency: measure_storage_latency,
      memory_usage: "2.1MB"     # Would need actual measurement
    }
  end
  
  def self.measure_storage_latency
    start = Time.current
    ThrottleMachines.limiter("latency_test", limit: 1, period: 1).allowed?
    ((Time.current - start) * 1000).round(2)
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