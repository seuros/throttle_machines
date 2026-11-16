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
    ThrottleMachines::RackMiddleware.throttle('test', limit: 2, period: 60 * ThrottleMachines::NS_PER_SECOND) do |req|
      "test:#{req.ip}"
    end
  end

  test 'debug middleware execution' do
    get '/health'
    assert_response :success
    assert_kind_of ThrottleMachines::Storage::Memory, ThrottleMachines.storage

    get '/health'
    assert_response :success

    # The third request from the same IP is over the limit of two.
    get '/health'
    assert_response :too_many_requests

    # A different IP has its own budget.
    get '/health', headers: { 'REMOTE_ADDR' => '1.2.3.4' }
    assert_response :success
  end
end
