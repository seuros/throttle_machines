# frozen_string_literal: true

require 'test_helper'
require 'throttle_machines/rack_middleware'

class MiddlewareTest < ActionDispatch::IntegrationTest
  setup do
    # Reset and configure middleware
    ThrottleMachines.reset!
    ThrottleMachines::RackMiddleware.clear!
    ThrottleMachines::RackMiddleware.enabled = true
  end

  test 'middleware is installed and working' do
    # Configure a very low limit
    ThrottleMachines::RackMiddleware.throttle('test', limit: 2, period: 60, &:ip)

    # First request should work
    get '/health'

    assert_response :success

    # Second request should work
    get '/health'

    assert_response :success

    # Third request should be rate limited
    get '/health'

    assert_response :too_many_requests
  end

  test 'rate limiting headers are present' do
    ThrottleMachines::RackMiddleware.throttle('test', limit: 10, period: 60, &:ip)

    get '/health'

    assert_response :success

    # Check for retry-after header when rate limited
    10.times { get '/health' }

    assert_response :too_many_requests
    assert_predicate response.headers['Retry-After'], :present?
  end
end
