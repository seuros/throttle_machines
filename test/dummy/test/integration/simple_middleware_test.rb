# frozen_string_literal: true

require 'test_helper'
require 'throttle_machines/rack_middleware'

class SimpleMiddlewareTest < ActionDispatch::IntegrationTest
  test 'middleware with default rules from initializer' do
    # Don't clear - use the rules from the initializer
    puts "Enabled: #{ThrottleMachines::RackMiddleware.enabled}"
    puts "Rules: #{ThrottleMachines::RackMiddleware.instance_variable_get(:@rules)}"

    # The payment endpoint has a limit of 10
    11.times do |i|
      get '/test/payment'
      puts "Request #{i + 1}: #{response.status}"
      if response.status == 429
        puts "Rate limited at request #{i + 1}!"
        break
      end
    end

    assert_equal 429, response.status, 'Should be rate limited after 10 requests'
  end
end
