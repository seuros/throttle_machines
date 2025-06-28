# frozen_string_literal: true

require 'test_helper'
require 'throttle_machines/rack_middleware'

class MiddlewareDebugTest < ActionDispatch::IntegrationTest
  setup do
    # Reset and configure middleware
    ThrottleMachines.reset!
    ThrottleMachines::RackMiddleware.clear!
    ThrottleMachines::RackMiddleware.enabled = true

    # Configure a simple throttle
    ThrottleMachines::RackMiddleware.throttle('test', limit: 2, period: 60) do |req|
      "test:#{req.ip}"
    end
  end

  test 'debug middleware execution' do
    # First request
    get '/health'
    puts "Response 1: #{response.status}"
    puts "Headers 1: #{response.headers.select { |k, _v| k.start_with?('X-') || k == 'Retry-After' }}"

    # Check storage
    storage = ThrottleMachines.configuration.storage
    puts "Storage class: #{storage.class}"
    puts "Storage contents after 1st request: #{storage.inspect}"

    # Second request
    get '/health'
    puts "Response 2: #{response.status}"

    # Third request should be rate limited
    get '/health'
    puts "Response 3: #{response.status}"
    puts "Headers 3: #{response.headers.select { |k, _v| k.start_with?('X-') || k == 'Retry-After' }}"

    # Try with a different key
    get '/health', headers: { 'REMOTE_ADDR' => '1.2.3.4' }
    puts "Response 4 (different IP): #{response.status}"
  end
end
