# frozen_string_literal: true

# Load ThrottleMachines
require 'throttle_machines'

# Every period is Integer nanoseconds.
MINUTE = 60 * ThrottleMachines::NS_PER_SECOND

# Memory storage for tests: allows us to see immediate results
ThrottleMachines.storage = ThrottleMachines::Storage::Memory.new

ThrottleMachines.configure do |config|
  config.instrumentation_enabled = true
end

# Only configure defaults if running the server, not tests
unless Rails.env.test?
  # Configure middleware with different rate limits for different endpoints
  # Basic endpoint: 10 requests per minute
  ThrottleMachines::RackMiddleware.throttle('basic/ip', limit: 10, period: MINUTE) do |req|
    req.path == '/rate_limit_test' && req.ip
  end

  # API endpoint: 5 requests per minute (more restrictive)
  ThrottleMachines::RackMiddleware.throttle('api/ip', limit: 5, period: MINUTE) do |req|
    req.path == '/api/rate_limit_test' && req.ip
  end

  # Status endpoint: 20 requests per minute
  ThrottleMachines::RackMiddleware.throttle('status/ip', limit: 20, period: MINUTE) do |req|
    req.path == '/rate_limit_status' && req.ip
  end

  # Health check: 100 requests per minute (less restrictive)
  ThrottleMachines::RackMiddleware.throttle('health/ip', limit: 100, period: MINUTE) do |req|
    req.path.start_with?('/health') && req.ip
  end
end

# Custom response for rate limited requests
ThrottleMachines::RackMiddleware.throttled_responder = lambda do |request|
  match_data = request.env['rack.attack.match_data'] || {}
  # retry_after is Integer nanoseconds; the header is whole seconds.
  wait = match_data[:retry_after] || (60 * ThrottleMachines::NS_PER_SECOND)
  retry_after = wait.ceildiv(ThrottleMachines::NS_PER_SECOND)

  [429, {
    'Content-Type' => 'application/json',
    'Retry-After' => retry_after.to_s,
    'X-RateLimit-Limit' => (match_data[:limit] || 0).to_s,
    'X-RateLimit-Remaining' => '0',
    'X-RateLimit-Reset' => (Time.now.to_i + retry_after).to_s
  }, [{
    error: 'Too Many Requests',
    message: 'Rate limit exceeded',
    retry_after: retry_after
  }.to_json]]
end
