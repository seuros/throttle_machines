# frozen_string_literal: true

require 'test_helper'
require 'throttle_machines/rack_middleware'

module ThrottleMachines
  class RackMiddlewareTest < Test
    def setup
      super
      ThrottleMachines::RackMiddleware.clear!
      ThrottleMachines::RackMiddleware.enabled = true
    end

    def test_basic_throttle
      app = ->(_env) { [200, {}, ['OK']] }

      # Configure throttle
      ThrottleMachines::RackMiddleware.throttle('req/ip', limit: 2, period: 60, &:ip)

      middleware = ThrottleMachines::RackMiddleware.new(app)

      # First two requests should succeed
      2.times do |i|
        status, = middleware.call(env_for('/', 'REMOTE_ADDR' => '1.2.3.4'))

        assert_equal 200, status, "Request #{i + 1} should succeed"
      end

      # Third request should be throttled
      status, headers, body = middleware.call(env_for('/', 'REMOTE_ADDR' => '1.2.3.4'))

      assert_equal 429, status
      assert headers['retry-after']
      assert_equal ["Retry later\n"], body
    end

    def test_blocklist
      app = ->(_env) { [200, {}, ['OK']] }

      # Block specific IP
      ThrottleMachines::RackMiddleware.blocklist_ip('1.2.3.4')

      middleware = ThrottleMachines::RackMiddleware.new(app)

      # Blocked IP should get 403
      status, _, body = middleware.call(env_for('/', 'REMOTE_ADDR' => '1.2.3.4'))

      assert_equal 403, status
      assert_equal ["Forbidden\n"], body

      # Other IPs should work
      status, = middleware.call(env_for('/', 'REMOTE_ADDR' => '5.6.7.8'))

      assert_equal 200, status
    end

    def test_safelist
      app = ->(_env) { [200, {}, ['OK']] }

      # Configure throttle
      ThrottleMachines::RackMiddleware.throttle('req/ip', limit: 1, period: 60, &:ip)

      # Safelist specific IP
      ThrottleMachines::RackMiddleware.safelist_ip('1.2.3.4')

      middleware = ThrottleMachines::RackMiddleware.new(app)

      # Safelisted IP should never be throttled
      3.times do
        status, = middleware.call(env_for('/', 'REMOTE_ADDR' => '1.2.3.4'))

        assert_equal 200, status
      end

      # Other IPs should be throttled
      status, = middleware.call(env_for('/', 'REMOTE_ADDR' => '5.6.7.8'))

      assert_equal 200, status

      status, = middleware.call(env_for('/', 'REMOTE_ADDR' => '5.6.7.8'))

      assert_equal 429, status
    end

    def test_track
      app = ->(_env) { [200, {}, ['OK']] }
      tracked_requests = []

      # Track requests
      ThrottleMachines::RackMiddleware.track('api/request') do |req|
        tracked_requests << req.path
        req.path.start_with?('/api') ? req.ip : nil
      end

      middleware = ThrottleMachines::RackMiddleware.new(app)

      # API request should be tracked but not blocked
      status, = middleware.call(env_for('/api/users', 'REMOTE_ADDR' => '1.2.3.4'))

      assert_equal 200, status
      assert_includes tracked_requests, '/api/users'

      # Non-API request should not be tracked
      status, = middleware.call(env_for('/home', 'REMOTE_ADDR' => '1.2.3.4'))

      assert_equal 200, status
    end

    def test_custom_throttled_response
      app = ->(_env) { [200, {}, ['OK']] }

      # Configure custom response
      ThrottleMachines::RackMiddleware.throttled_responder = lambda do |_request|
        [503, { 'content-type' => 'text/plain' }, ['Service Unavailable']]
      end

      ThrottleMachines::RackMiddleware.throttle('req/ip', limit: 1, period: 60, &:ip)

      middleware = ThrottleMachines::RackMiddleware.new(app)

      # First request OK
      middleware.call(env_for('/', 'REMOTE_ADDR' => '1.2.3.4'))

      # Second request gets custom response
      status, _, body = middleware.call(env_for('/', 'REMOTE_ADDR' => '1.2.3.4'))

      assert_equal 503, status
      assert_equal ['Service Unavailable'], body
    end

    def test_disabled
      app = ->(_env) { [200, {}, ['OK']] }

      # Disable rack attack
      ThrottleMachines::RackMiddleware.enabled = false

      ThrottleMachines::RackMiddleware.throttle('req/ip', limit: 1, period: 60, &:ip)

      middleware = ThrottleMachines::RackMiddleware.new(app)

      # All requests should pass through
      3.times do
        status, = middleware.call(env_for('/', 'REMOTE_ADDR' => '1.2.3.4'))

        assert_equal 200, status
      end
    end

    private

    def env_for(path, headers = {})
      {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => path,
        'rack.input' => StringIO.new,
        'rack.url_scheme' => 'http',
        'SERVER_NAME' => 'example.com',
        'SERVER_PORT' => '80'
      }.merge(headers)
    end
  end
end
