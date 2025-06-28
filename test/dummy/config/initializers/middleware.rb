# frozen_string_literal: true

require 'throttle_machines/rack_middleware'

# Configure ThrottleMachines middleware for the dummy app
ThrottleMachines::RackMiddleware.enabled = true

# Only configure default rules when not in test environment
# Tests will configure their own specific rules
unless Rails.env.test?
  # Configure rate limiting rules
  ThrottleMachines::RackMiddleware.throttle('ip', limit: 100, period: 60, &:ip)

  # Different limits for API endpoints
  ThrottleMachines::RackMiddleware.throttle('api', limit: 1000, period: 3600) do |req|
    "api:#{req.ip}" if req.path.start_with?('/api/')
  end

  # Aggressive limiting for payment endpoints
  ThrottleMachines::RackMiddleware.throttle('payment', limit: 10, period: 60) do |req|
    "payment:#{req.ip}" if req.path == '/test/payment'
  end
end

# Add the middleware to the Rails app
Rails.application.config.middleware.use ThrottleMachines::RackMiddleware
