# 🎮 Command Examples

> **Real Mission Scenarios** - Battle-tested configurations from the front lines of the cosmos

This mission log contains real-world examples of ThrottleMachines in action. Each scenario represents actual challenges faced by space-faring applications and their solutions.

---

## 🌌 Mission Scenarios

### Mission 1: API Gateway Defense System
**Objective**: Protect your API from various attack vectors while maintaining quality service for legitimate users.

```ruby
# config/initializers/api_defense.rb
class APIDefenseSystem
  def self.initialize!
    # Layer 1: Global rate limiting (the outer shield)
    ThrottleMachines::RackMiddleware.throttle("global_shield",
      limit: 10_000,
      period: 300,  # 10k requests per 5 minutes globally
      algorithm: :gcra  # Smooth distribution, no thundering herds
    ) do |req|
      "global"  # Single global key
    end
    
    # Layer 2: Per-IP rate limiting (individual ship tracking)
    ThrottleMachines::RackMiddleware.throttle("ip_tracker",
      limit: 1000,
      period: 300,  # 1k requests per 5 minutes per IP
      algorithm: :sliding_window  # Precise tracking for security
    ) do |req|
      req.ip
    end
    
    # Layer 3: Authenticated user limits (crew member privileges)
    ThrottleMachines::RackMiddleware.throttle("authenticated_crew",
      limit: 5000,
      period: 3600,  # 5k requests per hour for logged-in users
      algorithm: :token_bucket  # Allow bursts for power users
    ) do |req|
      # Extract user ID from JWT token
      token = req.env["HTTP_AUTHORIZATION"]&.split(" ")&.last
      user_id = decode_jwt(token)["user_id"] rescue nil
      user_id ? "user:#{user_id}" : nil
    end
    
    # Layer 4: Expensive endpoint protection (warp core safety)
    ThrottleMachines::RackMiddleware.throttle("expensive_operations",
      limit: 10,
      period: 60,  # Only 10 expensive operations per minute
      algorithm: :fixed_window
    ) do |req|
      if req.path =~ /\/(export|report|analyze)/
        req.ip  # Track by IP for expensive operations
      end
    end
    
    # Special Forces: GraphQL complexity limiting
    ThrottleMachines::RackMiddleware.throttle("graphql_complexity",
      limit: 1000,
      period: 60,  # 1000 complexity points per minute
      algorithm: :gcra
    ) do |req|
      if req.path == "/graphql" && req.post?
        # Calculate query complexity
        complexity = calculate_graphql_complexity(req.body)
        if complexity > 0
          "graphql:#{req.ip}:#{complexity}"  # Include complexity in key
        end
      end
    end
  end
  
  private
  
  def self.decode_jwt(token)
    # Your JWT decoding logic
    JWT.decode(token, Rails.application.secret_key_base)[0]
  end
  
  def self.calculate_graphql_complexity(body)
    # Parse GraphQL query and calculate complexity
    # This is a simplified example
    query = JSON.parse(body)["query"] rescue ""
    
    # Count fields and nested queries
    complexity = 0
    complexity += query.scan(/{/).count * 10  # Each level adds complexity
    complexity += query.scan(/\w+\s*{/).count * 5  # Each field selection
    complexity += query.scan(/\(.*\)/).count * 20  # Arguments are expensive
    
    complexity
  end
end

# Initialize on application start
APIDefenseSystem.initialize!
```

---

### Mission 2: AI Service Rate Limiting
**Objective**: Manage expensive AI/LLM API calls with tiered access and cost controls.

```ruby
# app/services/ai_throttle_system.rb
class AIThrottleSystem
  TIERS = {
    free: { 
      requests: 10, 
      tokens: 1000, 
      period: 86400,  # Daily limits
      model: "gpt-3.5-turbo"
    },
    pro: { 
      requests: 100, 
      tokens: 50_000, 
      period: 86400,
      model: "gpt-4"
    },
    enterprise: { 
      requests: 1000, 
      tokens: 500_000, 
      period: 86400,
      model: "gpt-4-turbo"
    }
  }.freeze
  
  def initialize(user)
    @user = user
    @tier = user.subscription_tier.to_sym
  end
  
  def process_request(prompt)
    # Check request count limit
    request_limiter = ThrottleMachines.limiter(
      "ai:requests:#{@user.id}",
      limit: TIERS[@tier][:requests],
      period: TIERS[@tier][:period],
      algorithm: :fixed_window  # Hard daily limit
    )
    
    unless request_limiter.allowed?
      return {
        error: "Daily request limit exceeded",
        limit: TIERS[@tier][:requests],
        resets_at: Time.current.end_of_day,
        upgrade_url: "/pricing"
      }
    end
    
    # Check token limit
    estimated_tokens = estimate_tokens(prompt)
    token_limiter = ThrottleMachines.limiter(
      "ai:tokens:#{@user.id}",
      limit: TIERS[@tier][:tokens],
      period: TIERS[@tier][:period],
      algorithm: :token_bucket  # Allow bursts within token limit
    )
    
    # Use multiple tokens at once
    if token_limiter.allowed?(count: estimated_tokens)
      # Process with circuit breaker protection
      response = ai_circuit_breaker.run do
        call_ai_api(prompt, model: TIERS[@tier][:model])
      end
      
      # Track actual usage
      track_usage(@user, response[:tokens_used])
      
      response
    else
      {
        error: "Token limit exceeded",
        tokens_remaining: token_limiter.remaining,
        estimated_tokens_needed: estimated_tokens,
        resets_at: Time.current.end_of_day
      }
    end
  rescue ThrottleMachines::CircuitOpenError => e
    # AI service is down, return cached or degraded response
    {
      error: "AI service temporarily unavailable",
      retry_after: e.retry_after,
      cached_response: fetch_cached_response(prompt)
    }
  end
  
  private
  
  def ai_circuit_breaker
    @ai_circuit_breaker ||= ThrottleMachines::Breaker.new(
      "openai_api",
      failure_threshold: 3,  # 3 failures
      timeout: 300,         # 5 minute recovery
      storage: ThrottleMachines.configuration.storage
    )
  end
  
  def estimate_tokens(prompt)
    # Rough estimation: ~4 characters per token
    (prompt.length / 4.0).ceil + 100  # +100 for response
  end
  
  def call_ai_api(prompt, model:)
    response = OpenAI::Client.new.completions(
      model: model,
      messages: [{ role: "user", content: prompt }],
      max_tokens: 1000
    )
    
    {
      content: response.dig("choices", 0, "message", "content"),
      tokens_used: response.dig("usage", "total_tokens"),
      model: model
    }
  end
  
  def track_usage(user, tokens_used)
    # Record usage for billing
    Usage.create!(
      user: user,
      service: "openai",
      tokens: tokens_used,
      cost: calculate_cost(tokens_used, @tier),
      timestamp: Time.current
    )
  end
  
  def fetch_cached_response(prompt)
    # Try to find similar previous response
    Rails.cache.fetch("ai:cached:#{Digest::MD5.hexdigest(prompt)}", expires_in: 1.hour) do
      "Service temporarily unavailable. Please try again later."
    end
  end
end

# Usage in controller
class AIController < ApplicationController
  before_action :authenticate_user!
  
  def generate
    ai_system = AIThrottleSystem.new(current_user)
    result = ai_system.process_request(params[:prompt])
    
    if result[:error]
      render json: result, status: 429
    else
      render json: result
    end
  end
end
```

---

### Mission 3: Multi-Tenant SaaS Platform
**Objective**: Implement fair resource allocation across different organizations with dynamic limits.

```ruby
# app/services/multi_tenant_throttle.rb
class MultiTenantThrottle
  def self.configure!
    # Dynamic per-tenant limiting
    ThrottleMachines::RackMiddleware.throttle("tenant_quota",
      limit: ->(req) { tenant_limit(req) },
      period: ->(req) { tenant_period(req) },
      algorithm: :gcra
    ) do |req|
      tenant_id = extract_tenant(req)
      tenant_id ? "tenant:#{tenant_id}" : nil
    end
    
    # Prevent noisy neighbors
    ThrottleMachines::RackMiddleware.throttle("noisy_neighbor_protection",
      limit: 10_000,
      period: 300,  # No single tenant can use more than 10k in 5 min
      algorithm: :sliding_window
    ) do |req|
      tenant_id = extract_tenant(req)
      tenant_id ? "tenant:burst:#{tenant_id}" : nil
    end
    
    # API endpoint specific limits per tenant
    ThrottleMachines::RackMiddleware.throttle("endpoint_limits",
      limit: ->(req) { endpoint_limit(req) },
      period: 60,
      algorithm: :token_bucket
    ) do |req|
      tenant_id = extract_tenant(req)
      endpoint = req.path.split("/")[2]  # /api/v1/[endpoint]
      tenant_id && endpoint ? "#{tenant_id}:#{endpoint}" : nil
    end
  end
  
  def self.tenant_limit(request)
    tenant = find_tenant(request)
    return 100 unless tenant  # Default for unknown tenants
    
    # Limits based on subscription plan
    case tenant.plan
    when "enterprise"
      100_000  # 100k requests per period
    when "business"  
      10_000   # 10k requests per period
    when "startup"
      1_000    # 1k requests per period
    when "trial"
      100      # 100 requests per period
    else
      10       # Minimal for expired/suspended
    end
  end
  
  def self.tenant_period(request)
    tenant = find_tenant(request)
    return 3600 unless tenant  # Default 1 hour
    
    # Different reset periods by plan
    case tenant.plan
    when "enterprise"
      300    # 5 minutes (more granular)
    when "business"
      900    # 15 minutes
    when "startup"
      3600   # 1 hour
    when "trial"
      86400  # 24 hours
    else
      86400  # 24 hours for restricted
    end
  end
  
  def self.endpoint_limit(request)
    tenant = find_tenant(request)
    endpoint = request.path.split("/")[2]
    
    return 10 unless tenant && endpoint
    
    # Different limits for different endpoints
    base_limit = case endpoint
    when "search"
      100  # Search is expensive
    when "export"
      10   # Exports are very expensive
    when "webhook"
      1000 # Webhooks can be frequent
    else
      500  # Default endpoint limit
    end
    
    # Adjust by plan
    multiplier = case tenant.plan
    when "enterprise" then 10
    when "business" then 5
    when "startup" then 2
    else 1
    end
    
    base_limit * multiplier
  end
  
  def self.extract_tenant(request)
    # Try multiple methods to identify tenant
    
    # Method 1: Subdomain (acme.example.com)
    subdomain = request.host.split('.').first
    return subdomain unless subdomain == 'www' || subdomain == 'api'
    
    # Method 2: Header (X-Tenant-ID)
    return request.env["HTTP_X_TENANT_ID"] if request.env["HTTP_X_TENANT_ID"]
    
    # Method 3: JWT claim
    if auth_header = request.env["HTTP_AUTHORIZATION"]
      token = auth_header.split(' ').last
      claims = JWT.decode(token, Rails.application.secret_key_base)[0] rescue {}
      return claims["tenant_id"] if claims["tenant_id"]
    end
    
    # Method 4: API key lookup
    if api_key = request.params["api_key"] || request.env["HTTP_X_API_KEY"]
      tenant = Tenant.joins(:api_keys).where(api_keys: { key: api_key }).first
      return tenant.id if tenant
    end
    
    nil
  end
  
  def self.find_tenant(request)
    tenant_id = extract_tenant(request)
    return nil unless tenant_id
    
    # Cache tenant lookups
    Rails.cache.fetch("tenant:#{tenant_id}", expires_in: 5.minutes) do
      Tenant.find_by(id: tenant_id) || Tenant.find_by(subdomain: tenant_id)
    end
  end
end

# Tenant-aware circuit breakers
class TenantCircuitBreaker
  def self.for_tenant(tenant_id, service)
    ThrottleMachines::Breaker.new(
      "tenant:#{tenant_id}:#{service}",
      failure_threshold: 5,
      timeout: 300,
      storage: ThrottleMachines.configuration.storage
    )
  end
  
  def self.protect(tenant_id, service, &block)
    breaker = for_tenant(tenant_id, service)
    
    breaker.run(&block)
  rescue ThrottleMachines::CircuitOpenError => e
    # Notify tenant admins
    TenantMailer.service_disruption(tenant_id, service, e.retry_after).deliver_later
    
    # Return degraded response
    {
      error: "Service temporarily unavailable for your organization",
      retry_after: e.retry_after,
      status: "degraded"
    }
  end
end
```

---

### Mission 4: Geographic Traffic Management
**Objective**: Route and limit traffic based on geographic regions with different regulations and capacity.

```ruby
# app/services/geographic_defense_grid.rb
class GeographicDefenseGrid
  REGIONS = {
    "NA" => { limit: 50_000, period: 300 },    # North America
    "EU" => { limit: 40_000, period: 300 },    # Europe (GDPR considerations)
    "AS" => { limit: 30_000, period: 300 },    # Asia
    "SA" => { limit: 10_000, period: 300 },    # South America
    "AF" => { limit: 5_000, period: 300 },     # Africa
    "OC" => { limit: 5_000, period: 300 },     # Oceania
    "AN" => { limit: 100, period: 300 }        # Antarctica (research stations only)
  }.freeze
  
  def self.configure!
    # Regional rate limiting
    ThrottleMachines::RackMiddleware.throttle("regional_limits",
      limit: ->(req) { region_limit(req) },
      period: ->(req) { REGIONS[detect_region(req)][:period] },
      algorithm: :gcra
    ) do |req|
      region = detect_region(req)
      "region:#{region}"
    end
    
    # Country-specific regulations
    ThrottleMachines::RackMiddleware.throttle("country_compliance",
      limit: ->(req) { country_limit(req) },
      period: 3600,
      algorithm: :fixed_window
    ) do |req|
      country = detect_country(req)
      restricted_countries.include?(country) ? "country:#{country}" : nil
    end
    
    # Data center proximity routing
    ThrottleMachines::RackMiddleware.throttle("datacenter_routing",
      limit: 1000,
      period: 60,
      algorithm: :token_bucket
    ) do |req|
      datacenter = nearest_datacenter(req.ip)
      "dc:#{datacenter}:#{req.ip}"
    end
    
    # GDPR-compliant limiting for EU
    ThrottleMachines::RackMiddleware.throttle("gdpr_compliance",
      limit: 100,
      period: 86400,  # Daily limit for data exports
      algorithm: :fixed_window
    ) do |req|
      if detect_region(req) == "EU" && req.path =~ /\/(export|download)/
        "gdpr:#{req.ip}"
      end
    end
  end
  
  def self.detect_region(request)
    # Use GeoIP database
    @geoip ||= MaxMind::GeoIP2::Reader.new('GeoLite2-City.mmdb')
    
    begin
      result = @geoip.city(request.ip)
      result.continent.code
    rescue => e
      Rails.logger.warn "GeoIP lookup failed: #{e.message}"
      "NA"  # Default to North America
    end
  end
  
  def self.detect_country(request)
    @geoip ||= MaxMind::GeoIP2::Reader.new('GeoLite2-City.mmdb')
    
    begin
      result = @geoip.city(request.ip)
      result.country.iso_code
    rescue
      "US"  # Default
    end
  end
  
  def self.region_limit(request)
    region = detect_region(request)
    REGIONS[region][:limit]
  end
  
  def self.country_limit(request)
    country = detect_country(request)
    
    # Special limits for certain countries
    case country
    when "CN"
      100   # Restricted access
    when "RU"
      500   # Limited access
    when "DE", "FR", "GB"
      5000  # EU data protection
    else
      1000  # Default
    end
  end
  
  def self.restricted_countries
    %w[CN RU KP IR SY]  # Example restricted countries
  end
  
  def self.nearest_datacenter(ip)
    region = detect_region_from_ip(ip)
    
    # Map regions to nearest datacenter
    case region
    when "NA" then "us-east-1"
    when "EU" then "eu-west-1"
    when "AS" then "ap-southeast-1"
    when "SA" then "sa-east-1"
    else "us-east-1"  # Default
    end
  end
  
  # Geographic circuit breakers
  def self.regional_circuit_breaker(region)
    ThrottleMachines::Breaker.new(
      "region:#{region}:circuit",
      failure_threshold: 10,
      timeout: 600,  # 10 minute recovery
      storage: ThrottleMachines.configuration.storage
    )
  end
  
  # Health monitoring by region
  def self.regional_health
    REGIONS.keys.map do |region|
      breaker = regional_circuit_breaker(region)
      limiter = ThrottleMachines.limiter("region:#{region}", 
        limit: REGIONS[region][:limit], 
        period: REGIONS[region][:period]
      )
      
      {
        region: region,
        circuit_status: breaker.state,
        current_usage: limiter.current_count,
        usage_percentage: (limiter.current_count.to_f / REGIONS[region][:limit] * 100).round(2),
        healthy: breaker.state == :closed && limiter.current_count < REGIONS[region][:limit] * 0.8
      }
    end
  end
end

# Geographic monitoring job
class GeographicMonitoringJob < ApplicationJob
  queue_as :monitoring
  
  def perform
    health_report = GeographicDefenseGrid.regional_health
    
    # Alert on unhealthy regions
    unhealthy_regions = health_report.reject { |r| r[:healthy] }
    
    if unhealthy_regions.any?
      OpsMailer.regional_health_alert(unhealthy_regions).deliver_later
      
      # Auto-scale if possible
      unhealthy_regions.each do |region|
        if region[:usage_percentage] > 90
          AutoScaler.scale_up_region(region[:region])
        end
      end
    end
    
    # Store metrics
    health_report.each do |region|
      RegionalMetric.create!(
        region: region[:region],
        usage_percentage: region[:usage_percentage],
        circuit_state: region[:circuit_status],
        timestamp: Time.current
      )
    end
  end
end
```

---

### Mission 5: WebSocket & Real-time Connection Management
**Objective**: Manage persistent connections and real-time features with appropriate limits.

```ruby
# app/services/realtime_throttle_system.rb
class RealtimeThrottleSystem
  def self.configure_websocket_limits
    # Connection limits per user
    @connection_limiter = ThrottleMachines.limiter(
      "websocket:connections",
      limit: 5,  # Max 5 concurrent connections per user
      period: 0, # Concurrent limit, not time-based
      algorithm: :fixed_window
    )
    
    # Message rate limiting
    @message_limiter = ThrottleMachines.limiter(
      "websocket:messages",
      limit: 100,
      period: 60,  # 100 messages per minute
      algorithm: :gcra  # Smooth message flow
    )
    
    # Subscription limits
    @subscription_limiter = ThrottleMachines.limiter(
      "websocket:subscriptions",
      limit: 50,  # Max 50 channel subscriptions
      period: 0,  # Concurrent limit
      algorithm: :fixed_window
    )
  end
  
  # ActionCable connection class
  class ApplicationCable::Connection < ActionCable::Connection::Base
    identified_by :current_user
    
    def connect
      self.current_user = find_verified_user
      
      # Check connection limit
      if connection_allowed?
        track_connection
        logger.add_tags 'ActionCable', current_user.id
      else
        reject_over_limit
      end
    end
    
    def disconnect
      release_connection
    end
    
    private
    
    def find_verified_user
      if verified_user = User.find_by(id: cookies.signed[:user_id])
        verified_user
      else
        reject_unauthorized_connection
      end
    end
    
    def connection_allowed?
      limiter = ThrottleMachines.limiter(
        "ws:conn:#{current_user.id}",
        limit: connection_limit_for_user,
        period: 0,
        algorithm: :fixed_window
      )
      
      limiter.allowed?
    end
    
    def connection_limit_for_user
      case current_user.subscription_tier
      when "enterprise" then 20
      when "pro" then 10
      when "basic" then 5
      else 2
      end
    end
    
    def track_connection
      Redis.current.sadd("connections:#{current_user.id}", connection_identifier)
      Redis.current.expire("connections:#{current_user.id}", 1.hour)
    end
    
    def release_connection
      Redis.current.srem("connections:#{current_user.id}", connection_identifier)
    end
    
    def reject_over_limit
      logger.warn "Connection limit exceeded for user #{current_user.id}"
      reject_unauthorized_connection
    end
  end
  
  # Channel-specific throttling
  class ApplicationCable::Channel < ActionCable::Channel::Base
    def subscribed
      if subscription_allowed?
        track_subscription
        stream_from specific_channel
      else
        reject_subscription("Subscription limit exceeded")
      end
    end
    
    def receive(data)
      if message_allowed?
        process_message(data)
      else
        transmit({ 
          error: "Message rate limit exceeded", 
          retry_after: message_limiter.retry_after 
        })
      end
    end
    
    def unsubscribed
      release_subscription
    end
    
    private
    
    def subscription_allowed?
      limiter = ThrottleMachines.limiter(
        "ws:subs:#{current_user.id}",
        limit: subscription_limit_for_user,
        period: 0,
        algorithm: :fixed_window
      )
      
      limiter.allowed?
    end
    
    def message_allowed?
      message_limiter.allowed?
    end
    
    def message_limiter
      @message_limiter ||= ThrottleMachines.limiter(
        "ws:msg:#{current_user.id}:#{specific_channel}",
        limit: message_limit_for_channel,
        period: 60,
        algorithm: :gcra
      )
    end
    
    def message_limit_for_channel
      case self.class.name
      when "ChatChannel" then 60      # 1 message per second
      when "NotificationChannel" then 10  # Receive-only mostly
      when "DataChannel" then 30      # Moderate updates
      else 20
      end
    end
    
    def reject_subscription(reason)
      logger.warn "Subscription rejected for #{current_user.id}: #{reason}"
      reject
    end
  end
  
  # Presence tracking with limits
  class PresenceThrottle
    def self.track_presence(user_id, channel)
      # Limit presence updates
      limiter = ThrottleMachines.limiter(
        "presence:#{user_id}:#{channel}",
        limit: 10,
        period: 60,  # 10 presence updates per minute
        algorithm: :sliding_window
      )
      
      if limiter.allowed?
        update_presence(user_id, channel)
        broadcast_presence_change(channel)
      end
    end
    
    def self.update_presence(user_id, channel)
      key = "presence:#{channel}"
      Redis.current.zadd(key, Time.current.to_i, user_id)
      Redis.current.expire(key, 5.minutes)
      
      # Cleanup old entries
      Redis.current.zremrangebyscore(key, 0, 5.minutes.ago.to_i)
    end
    
    def self.broadcast_presence_change(channel)
      # Throttle presence broadcasts per channel
      broadcast_limiter = ThrottleMachines.limiter(
        "presence:broadcast:#{channel}",
        limit: 5,
        period: 10,  # Max 5 broadcasts per 10 seconds per channel
        algorithm: :token_bucket
      )
      
      if broadcast_limiter.allowed?
        ActionCable.server.broadcast(channel, {
          type: "presence_update",
          users: get_present_users(channel)
        })
      end
    end
  end
  
  # Circuit breaker for WebSocket infrastructure
  def self.websocket_circuit_breaker
    @ws_breaker ||= ThrottleMachines::Breaker.new(
      "websocket_infrastructure",
      failure_threshold: 10,
      timeout: 300,
      storage: ThrottleMachines.configuration.storage
    )
  end
  
  # Health monitoring
  def self.connection_health
    {
      total_connections: Redis.current.keys("connections:*").count,
      connections_by_tier: connection_breakdown,
      message_rate: calculate_message_rate,
      circuit_status: websocket_circuit_breaker.state,
      infrastructure_healthy: infrastructure_check
    }
  end
  
  private
  
  def self.connection_breakdown
    User.group(:subscription_tier).count.map do |tier, count|
      active = Redis.current.keys("connections:*").count { |k|
        user_id = k.split(":").last
        User.find(user_id).subscription_tier == tier rescue false
      }
      
      { tier: tier, total_users: count, active_connections: active }
    end
  end
  
  def self.calculate_message_rate
    # Get message counts from last minute
    keys = Redis.current.keys("throttle:ws:msg:*")
    total = keys.sum { |k| Redis.current.get(k).to_i }
    
    total.to_f / 60  # Messages per second
  end
  
  def self.infrastructure_check
    begin
      # Test ActionCable Redis connection
      ActionCable.server.pubsub.redis.ping
      true
    rescue
      false
    end
  end
end
```

---

## 🚀 Quick Reference Card

### Common Patterns Cheat Sheet
```ruby
# Basic rate limiting
limiter = ThrottleMachines.limiter("basic", limit: 100, period: 60)

# Smooth API traffic (no thundering herds)
gcra = ThrottleMachines.limiter("api", limit: 1000, period: 60, algorithm: :gcra)

# Allow bursts
bucket = ThrottleMachines.limiter("burst", limit: 50, period: 50, algorithm: :token_bucket)

# Circuit breaker for external services
breaker = ThrottleMachines::Breaker.new("external", failure_threshold: 5, timeout: 300)

# Rack middleware - complete defense
ThrottleMachines::RackMiddleware.throttle("defense", limit: 1000, period: 300) { |r| r.ip }
ThrottleMachines::RackMiddleware.blocklist("bad_actors") { |r| BadIP.exists?(r.ip) }
ThrottleMachines::RackMiddleware.safelist("good_guys") { |r| r.ip == "127.0.0.1" }

# Rails controller integration
class ApiController < ApplicationController
  include ThrottleMachines::Rails::Controller
  throttle :api_limit, limit: 100, period: 3600 do |request|
    current_user&.id || request.remote_ip
  end
end

# Dynamic limits
ThrottleMachines::RackMiddleware.throttle("dynamic",
  limit: ->(req) { User.find_by(api_key: req.headers["X-API-Key"])&.rate_limit || 100 },
  period: 3600
) { |req| req.headers["X-API-Key"] }

# Testing utilities
time_machine = TimeMachine.new
time_machine.advance(61.seconds)
time_machine.return_to_present
```

---

## 🎖️ Mission Accomplished

You now have battle-tested configurations for:
- ✅ API Gateway protection
- ✅ AI/LLM service management
- ✅ Multi-tenant platforms
- ✅ Geographic traffic routing
- ✅ Real-time WebSocket limiting

Remember: **"The best defense is a good throttle!"**

---

**"These examples aren't just code - they're lessons learned from a thousand production battles."**

*— Veteran Systems Engineer's Field Guide*
