# frozen_string_literal: true

require 'test_helper'
require 'throttle_machines/rack_middleware'

class RateLimitTestControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Reset rate limit storage before each test
    ThrottleMachines.reset!
    ThrottleMachines::RackMiddleware.clear!
    ThrottleMachines::RackMiddleware.enabled = true

    # Reconfigure the rules for testing
    ThrottleMachines::RackMiddleware.throttle('ip', limit: 100, period: 60, &:ip)

    ThrottleMachines::RackMiddleware.throttle('api', limit: 1000, period: 3600) do |req|
      "api:#{req.ip}" if req.path.start_with?('/api/')
    end

    ThrottleMachines::RackMiddleware.throttle('payment', limit: 10, period: 60) do |req|
      "payment:#{req.ip}" if req.path == '/test/payment'
    end
  end

  test 'basic rate limiting works' do
    # Should allow requests up to the limit
    10.times do
      get '/rate_limit_test'

      assert_response :success
    end
  end

  test 'exceeding rate limit returns 429' do
    # Set a lower limit for testing
    ThrottleMachines::RackMiddleware.clear!
    ThrottleMachines::RackMiddleware.throttle('test', limit: 5, period: 60, &:ip)

    # Make 5 requests (should all succeed)
    5.times do |i|
      get '/rate_limit_test'

      assert_response :success, "Request #{i + 1} should succeed"
    end

    # 6th request should be rate limited
    get '/rate_limit_test'

    assert_response :too_many_requests
    assert response.headers['Retry-After']
  end

  test 'API endpoint has different rate limits' do
    # API endpoints should allow more requests
    50.times do
      get '/api/rate_limit_test'

      assert_response :success
    end
  end

  test 'payment endpoint has strict rate limits' do
    # Payment endpoint allows only 10 requests per minute
    10.times do |i|
      get '/test/payment'
      # Could be success or rate limited depending on ExternalApiService behavior
      assert_includes [200, 429], response.status, "Request #{i + 1} status should be 200 or 429"
    end

    # 11th request should definitely be rate limited by middleware
    get '/test/payment'

    assert_response :too_many_requests
  end

  test 'rate limit applies per IP address' do
    # Requests from different IPs should have separate limits
    ThrottleMachines::RackMiddleware.clear!
    ThrottleMachines::RackMiddleware.throttle('test', limit: 2, period: 60, &:ip)

    # Make 2 requests from IP 1
    2.times do
      get '/rate_limit_test', headers: { 'REMOTE_ADDR' => '1.2.3.4' }

      assert_response :success
    end

    # 3rd request from IP 1 should be blocked
    get '/rate_limit_test', headers: { 'REMOTE_ADDR' => '1.2.3.4' }

    assert_response :too_many_requests

    # But request from IP 2 should work
    get '/rate_limit_test', headers: { 'REMOTE_ADDR' => '5.6.7.8' }

    assert_response :success
  end
end
