# frozen_string_literal: true

require 'test_helper'
require 'throttle_machines/rack_middleware'

class SimpleRateLimitTest < ActionDispatch::IntegrationTest
  def setup
    # Start fresh
    ThrottleMachines.reset!
    ThrottleMachines::RackMiddleware.clear!
    ThrottleMachines::RackMiddleware.enabled = true

    # Configure a simple throttle
    ThrottleMachines::RackMiddleware.throttle('simple', limit: 3, period: 60) do |_req|
      'simple_test' # Same key for all requests
    end
  end

  test 'simple rate limit works' do
    puts "\n=== Simple Rate Limit Test ==="
    puts "Configured throttles: #{ThrottleMachines::RackMiddleware.throttles.keys.inspect}"

    # Make 3 requests - should all succeed
    3.times do |i|
      get '/health'
      puts "Request #{i + 1}: #{response.status}"

      assert_response :success, "Request #{i + 1} should succeed"
    end

    # 4th request should fail
    get '/health'
    puts "Request 4: #{response.status}"
    puts "Response body: #{response.body}"
    puts "Headers: #{response.headers.to_h.select { |k, _v| k.start_with?('X-') || k == 'Retry-After' }}"

    assert_response :too_many_requests, 'Request 4 should be rate limited'
  end
end
