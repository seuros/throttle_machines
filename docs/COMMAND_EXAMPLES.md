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
  NS = ThrottleMachines::NS_PER_SECOND # spans are Integer nanoseconds

  def self.initialize!
    # Layer 1: Global rate limiting (the outer shield)
    ThrottleMachines::RackMiddleware.throttle("global_shield",
      limit: 10_000,
      period: 300 * NS,  # 10k requests per 5 minutes globally
      algorithm: :gcra  # Smooth distribution, no thundering herds
    ) do |req|
      "global"  # Single global key
    end

    # Layer 2: Per-IP rate limiting (individual ship tracking)
    ThrottleMachines::RackMiddleware.throttle("ip_tracker",
      limit: 1000,
      period: 300 * NS,  # 1k requests per 5 minutes per IP
      algorithm: :gcra  # Precise, evenly spaced tracking for security
    ) do |req|
      req.ip
    end

    # Layer 3: Authenticated user limits (crew member privileges)
    ThrottleMachines::RackMiddleware.throttle("authenticated_crew",
      limit: 5000,
      period: 3600 * NS,  # 5k requests per hour for logged-in users
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
      period: 60 * NS,  # Only 10 expensive operations per minute
      algorithm: :fixed_window
    ) do |req|
      if req.path =~ /\/(export|report|analyze)/
        req.ip  # Track by IP for expensive operations
      end
    end

    # Special Forces: GraphQL complexity limiting
    ThrottleMachines::RackMiddleware.throttle("graphql_complexity",
      limit: 1000,
      period: 60 * NS,  # 1000 complexity points per minute
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
  NS = ThrottleMachines::NS_PER_SECOND
  DAY = 86_400 * NS

  TIERS = {
    free: {
      requests: 10,
      tokens: 1000,
      period: DAY,  # Daily limits
      model: "gpt-3.5-turbo"
    },
    pro: {
      requests: 100,
      tokens: 50_000,
      period: DAY,
      model: "gpt-4"
    },
    enterprise: {
      requests: 1000,
      tokens: 500_000,
      period: DAY,
      model: "gpt-4-turbo"
    }
  }.freeze

  def initialize(user)
    @user = user
    @tier = user.subscription_tier.to_sym
  end

  def process_request(prompt)
    # Check the token budget first: limiters admit one call at a time, so a
    # multi-token budget is read off the usage ledger instead
    estimated_tokens = estimate_tokens(prompt)
    tokens_used = Usage.where(user: @user, service: "openai")
                       .where(timestamp: Time.current.beginning_of_day..).sum(:tokens)
    tokens_remaining = TIERS[@tier][:tokens] - tokens_used

    if estimated_tokens > tokens_remaining
      return {
        error: "Token limit exceeded",
        tokens_remaining: tokens_remaining,
        estimated_tokens_needed: estimated_tokens,
        resets_at: Time.current.end_of_day
      }
    end

    # Spend one request from the daily quota (raises ThrottledError when empty)
    ThrottleMachines.limiter(
      "ai:requests:#{@user.id}",
      limit: TIERS[@tier][:requests],
      period: TIERS[@tier][:period],
      algorithm: :fixed_window  # Hard daily limit
    ).throttle!

    # Process with circuit breaker protection
    response = ai_circuit_breaker.call do
      call_ai_api(prompt, model: TIERS[@tier][:model])
    end

    # Track actual usage
    track_usage(@user, response[:tokens_used])

    response
  rescue ThrottleMachines::ThrottledError => e
    {
      error: "Daily request limit exceeded",
      limit: TIERS[@tier][:requests],
      retry_after: e.retry_after.ceildiv(NS),  # ns -> whole seconds for clients
      upgrade_url: "/pricing"
    }
  rescue ThrottleMachines::CircuitOpenError => e
    # AI service is down, return cached or degraded response
    {
      error: "AI service temporarily unavailable",
      retry_after: e.retry_after&.ceildiv(NS),  # ns -> whole seconds
      cached_response: fetch_cached_response(prompt)
    }
  end

  private

  def ai_circuit_breaker
    # Registry-shared circuit: 3 failures within a minute, 5 minute recovery
    @ai_circuit_breaker ||= ThrottleMachines::Breakers.dynamic(
      "openai_api", self, 3, 60 * NS, 300 * NS
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
    Rails.cache.fetch("ai:cached:#{Digest::MD5.hexdigest(prompt)}", expires_in: 3600) do  # Rails.cache TTL, seconds
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
  NS = ThrottleMachines::NS_PER_SECOND

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
      period: 300 * NS,  # No single tenant can use more than 10k in 5 min
      algorithm: :gcra
    ) do |req|
      tenant_id = extract_tenant(req)
      tenant_id ? "tenant:burst:#{tenant_id}" : nil
    end

    # API endpoint specific limits per tenant
    ThrottleMachines::RackMiddleware.throttle("endpoint_limits",
      limit: ->(req) { endpoint_limit(req) },
      period: 60 * NS,
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
    return 3600 * NS unless tenant  # Default 1 hour

    # Different reset periods by plan (Integer nanoseconds)
    case tenant.plan
    when "enterprise"
      300 * NS     # 5 minutes (more granular)
    when "business"
      900 * NS     # 15 minutes
    when "startup"
      3600 * NS    # 1 hour
    when "trial"
      86_400 * NS  # 24 hours
    else
      86_400 * NS  # 24 hours for restricted
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
    Rails.cache.fetch("tenant:#{tenant_id}", expires_in: 300) do  # Rails.cache TTL, seconds
      Tenant.find_by(id: tenant_id) || Tenant.find_by(subdomain: tenant_id)
    end
  end
end

# Tenant-aware circuit breakers
class TenantCircuitBreaker
  NS = ThrottleMachines::NS_PER_SECOND

  def self.protect(tenant_id, service, &block)
    # One registry-shared circuit per tenant and service:
    # 5 failures within a minute opens it for 5 minutes
    ThrottleMachines.break_circuit("tenant:#{tenant_id}:#{service}",
      failures: 5,
      within: 60 * NS,
      timeout: 300 * NS,
      &block)
  rescue ThrottleMachines::CircuitOpenError => e
    wait = e.retry_after&.ceildiv(NS)  # ns -> whole seconds

    # Notify tenant admins
    TenantMailer.service_disruption(tenant_id, service, wait).deliver_later

    # Return degraded response
    {
      error: "Service temporarily unavailable for your organization",
      retry_after: wait,
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
  NS = ThrottleMachines::NS_PER_SECOND
  WINDOW = 300 * NS  # 5 minutes

  REGIONS = {
    "NA" => { limit: 50_000, period: WINDOW },  # North America
    "EU" => { limit: 40_000, period: WINDOW },  # Europe (GDPR considerations)
    "AS" => { limit: 30_000, period: WINDOW },  # Asia
    "SA" => { limit: 10_000, period: WINDOW },  # South America
    "AF" => { limit: 5_000, period: WINDOW },   # Africa
    "OC" => { limit: 5_000, period: WINDOW },   # Oceania
    "AN" => { limit: 100, period: WINDOW }      # Antarctica (research stations only)
  }.freeze

  def self.configure!
    # Regional rate limiting
    ThrottleMachines::RackMiddleware.throttle("regional_limits",
      limit: ->(req) { region_limit(req) },
      period: ->(req) { REGIONS[detect_region(req)][:period] },
      algorithm: :fixed_window  # Countable windows feed the health report below
    ) do |req|
      region = detect_region(req)
      "region:#{region}"
    end

    # Country-specific regulations
    ThrottleMachines::RackMiddleware.throttle("country_compliance",
      limit: ->(req) { country_limit(req) },
      period: 3600 * NS,
      algorithm: :fixed_window
    ) do |req|
      country = detect_country(req)
      restricted_countries.include?(country) ? "country:#{country}" : nil
    end

    # Data center proximity routing
    ThrottleMachines::RackMiddleware.throttle("datacenter_routing",
      limit: 1000,
      period: 60 * NS,
      algorithm: :token_bucket
    ) do |req|
      datacenter = nearest_datacenter(req.ip)
      "dc:#{datacenter}:#{req.ip}"
    end

    # GDPR-compliant limiting for EU
    ThrottleMachines::RackMiddleware.throttle("gdpr_compliance",
      limit: 100,
      period: 86_400 * NS,  # Daily limit for data exports
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
    # 10 failures within a minute, 10 minute recovery
    ThrottleMachines::Breakers.dynamic(
      "region:#{region}:circuit", self, 10, 60 * NS, 600 * NS
    )
  end

  # Health monitoring by region
  def self.regional_health
    REGIONS.keys.map do |region|
      breaker = regional_circuit_breaker(region)
      # Same key and shape the middleware uses ("<throttle name>:<discriminator>")
      limiter = ThrottleMachines.limiter("regional_limits:region:#{region}",
        limit: REGIONS[region][:limit],
        period: REGIONS[region][:period],
        algorithm: :fixed_window
      )

      current_usage = limiter.limit - limiter.remaining

      {
        region: region,
        circuit_status: breaker.state,
        current_usage: current_usage,
        usage_percentage: (current_usage.to_f / limiter.limit * 100).round(2),
        healthy: breaker.closed? && current_usage < limiter.limit * 0.8
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
  NS = ThrottleMachines::NS_PER_SECOND

  # Limiters count calls per period (a positive Integer of nanoseconds), so
  # they meter rates. Concurrent caps (open connections, live subscriptions)
  # are a gauge, not a rate: count them in Redis sets and compare.
  def self.configure_websocket_limits
    # Message rate limiting
    @message_limiter = ThrottleMachines.limiter(
      "websocket:messages",
      limit: 100,
      period: 60 * NS,  # 100 messages per minute
      algorithm: :gcra  # Smooth message flow
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
      # Concurrent cap: a gauge of open connections, not a rate limiter
      Redis.current.scard("connections:#{current_user.id}") < connection_limit_for_user
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
      Redis.current.expire("connections:#{current_user.id}", 3600)  # Redis TTL, seconds
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
          retry_after: message_limiter.retry_after.ceildiv(NS)  # ns -> whole seconds
        })
      end
    end

    def unsubscribed
      release_subscription
    end

    private

    def subscription_allowed?
      # Concurrent cap again: count live subscriptions, don't rate-limit them
      Redis.current.scard("subscriptions:#{current_user.id}") < subscription_limit_for_user
    end

    def message_allowed?
      message_limiter.throttle!  # Spend one message from the budget
      true
    rescue ThrottleMachines::ThrottledError
      false
    end

    def message_limiter
      @message_limiter ||= ThrottleMachines.limiter(
        "ws:msg:#{current_user.id}:#{specific_channel}",
        limit: message_limit_for_channel,
        period: 60 * NS,
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
        period: 60 * NS,  # 10 presence updates per minute
        algorithm: :gcra
      )

      limiter.throttle! do
        update_presence(user_id, channel)
        broadcast_presence_change(channel)
      end
    rescue ThrottleMachines::ThrottledError
      # Too chatty: drop this presence update
    end

    def self.update_presence(user_id, channel)
      key = "presence:#{channel}"
      now = Time.current.to_i  # Redis scores and TTLs are wall-clock seconds
      Redis.current.zadd(key, now, user_id)
      Redis.current.expire(key, 300)

      # Cleanup old entries
      Redis.current.zremrangebyscore(key, 0, now - 300)
    end

    def self.broadcast_presence_change(channel)
      # Throttle presence broadcasts per channel
      broadcast_limiter = ThrottleMachines.limiter(
        "presence:broadcast:#{channel}",
        limit: 5,
        period: 10 * NS,  # Max 5 broadcasts per 10 seconds per channel
        algorithm: :token_bucket
      )

      broadcast_limiter.throttle! do
        ActionCable.server.broadcast(channel, {
          type: "presence_update",
          users: get_present_users(channel)
        })
      end
    rescue ThrottleMachines::ThrottledError
      # Bucket empty: the next update carries the latest presence anyway
    end
  end

  # Circuit breaker for WebSocket infrastructure
  def self.websocket_circuit_breaker
    # 10 failures within a minute, 5 minute recovery
    @ws_breaker ||= ThrottleMachines::Breakers.dynamic(
      "websocket_infrastructure", self, 10, 60 * NS, 300 * NS
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

  # GCRA keeps a theoretical arrival time per key, not a counter, so count
  # admitted messages off the instrumentation stream instead
  ActiveSupport::Notifications.subscribe("rate_limit.allowed.throttle_machines") do |*, payload|
    if payload[:key].start_with?("ws:msg:")
      minute = Time.current.to_i / 60
      Redis.current.incr("ws:msg:count:#{minute}")
      Redis.current.expire("ws:msg:count:#{minute}", 120)  # Redis TTL, seconds
    end
  end

  def self.calculate_message_rate
    # Messages admitted during the last full minute
    total = Redis.current.get("ws:msg:count:#{Time.current.to_i / 60 - 1}").to_i

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
NS = ThrottleMachines::NS_PER_SECOND  # every span is Integer nanoseconds

# Basic rate limiting
limiter = ThrottleMachines.limiter("basic", limit: 100, period: 60 * NS)

# Smooth API traffic (no thundering herds)
gcra = ThrottleMachines.limiter("api", limit: 1000, period: 60 * NS, algorithm: :gcra)

# Allow bursts
bucket = ThrottleMachines.limiter("burst", limit: 50, period: 50 * NS, algorithm: :token_bucket)

# Circuit breaker for external services: 5 failures within a minute, 5 minute cooldown
ThrottleMachines.break_circuit("external", failures: 5, within: 60 * NS, timeout: 300 * NS) do
  ExternalService.call
end

# Rack middleware - complete defense
ThrottleMachines::RackMiddleware.throttle("defense", limit: 1000, period: 300 * NS) { |r| r.ip }
ThrottleMachines::RackMiddleware.blocklist("bad_actors") { |r| BadIP.exists?(r.ip) }
ThrottleMachines::RackMiddleware.safelist("good_guys") { |r| r.ip == "127.0.0.1" }

# Rails controller integration
class ApiController < ApplicationController
  include ThrottleMachines::ControllerHelpers
  before_action { throttle!(limit: 100, period: 3600 * NS) }  # keyed by user, else IP
end

# Dynamic limits
ThrottleMachines::RackMiddleware.throttle("dynamic",
  limit: ->(req) { User.find_by(api_key: req.get_header("HTTP_X_API_KEY"))&.rate_limit || 100 },
  period: 3600 * NS
) { |req| req.get_header("HTTP_X_API_KEY") }

# Testing utilities: pin the ship's clock (Integer ns), wipe state between tests
now = 0
ThrottleMachines.stub(:monotonic_time, -> { now }) do
  limiter.throttle!
  now += 61 * NS  # jump past the window
end
ThrottleMachines.reset!
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
