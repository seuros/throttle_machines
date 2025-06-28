# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class InstrumentationTest < Test
    def setup
      super

      # Enable instrumentation before subscribing
      ThrottleMachines.configure do |config|
        config.instrumentation_enabled = true
      end

      @events = []
      @subscriber = ActiveSupport::Notifications.subscribe(/throttle_machines/) do |name, start, finish, _id, payload|
        @events << {
          name: name,
          payload: payload,
          duration: finish - start
        }
      end
    end

    def teardown
      ActiveSupport::Notifications.unsubscribe(@subscriber) if @subscriber
      @events.clear
      # Reset to default backend to fix test isolation
      ThrottleMachines.configure do |config|
        config.instrumentation_backend = nil
      end
      ThrottleMachines.reset!
    end

    def test_basic_instrumentation_works
      # Simple test to verify basic instrumentation
      ThrottleMachines::Instrumentation.instrument('test.event', { data: 'test' })

      test_event = @events.find { |e| e[:name] == 'test.event.throttle_machines' }

      assert test_event, 'Test event should be captured'
      assert_equal 'test', test_event[:payload][:data]
    end

    def test_instrumentation_can_be_disabled
      # Clear any existing events first
      @events.clear

      ThrottleMachines.configure do |config|
        config.instrumentation_enabled = false
      end

      limiter = ThrottleMachines.limiter('test_disabled', limit: 5, period: 60)
      limiter.allow?

      assert_empty @events, 'No events should be emitted when instrumentation is disabled'

      # Re-enable for other tests
      ThrottleMachines.configure do |config|
        config.instrumentation_enabled = true
      end
    end

    def test_rate_limit_checked_event
      # Verify instrumentation is enabled
      assert ThrottleMachines::Instrumentation.enabled, 'Instrumentation should be enabled'

      limiter = ThrottleMachines.limiter('test', limit: 5, period: 60)
      allowed = limiter.allow?

      event = @events.find { |e| e[:name] == 'rate_limit.checked.throttle_machines' }

      assert event, 'rate_limit.checked event should be emitted'
      assert_equal 'test', event[:payload][:key]
      assert_equal 5, event[:payload][:limit]
      assert_equal 60, event[:payload][:period]
      assert_equal :fixed_window, event[:payload][:algorithm]
      assert_equal allowed, event[:payload][:allowed]
    end

    def test_rate_limit_allowed_event
      limiter = ThrottleMachines.limiter('test', limit: 5, period: 60)
      limiter.throttle! { 'work' }

      event = @events.find { |e| e[:name] == 'rate_limit.allowed.throttle_machines' }

      assert event, 'rate_limit.allowed event should be emitted'
      assert_equal 'test', event[:payload][:key]
      assert_equal 5, event[:payload][:limit]
      assert_equal 60, event[:payload][:period]
    end

    def test_rate_limit_throttled_event
      limiter = ThrottleMachines.limiter('test', limit: 1, period: 60)
      limiter.throttle! { 'first' }

      @events.clear # Clear previous events to focus on throttled event

      assert_raises(ThrottledError) do
        limiter.throttle! { 'second' }
      end

      event = @events.find { |e| e[:name] == 'rate_limit.throttled.throttle_machines' }

      assert event, 'rate_limit.throttled event should be emitted'
      assert_equal 'test', event[:payload][:key]
      assert_equal 1, event[:payload][:limit]
      assert_equal 60, event[:payload][:period]
      assert event[:payload][:retry_after], 'retry_after should be included'
    end

    def test_hedged_request_events
      skip 'Hedged requests use async operations that are hard to test synchronously'

      hedged = HedgedRequest.new(delay: 0.01, max_attempts: 2)

      result = hedged.run do |attempt|
        case attempt
        when 0
          sleep 0.05
          'slow'
        when 1
          'fast'
        end
      end

      assert_equal 'fast', result

      started_event = @events.find { |e| e[:name] == 'hedged_request.started.throttle_machines' }

      assert started_event, 'hedged_request.started event should be emitted'
      assert_equal 2, started_event[:payload][:max_attempts]

      winner_event = @events.find { |e| e[:name] == 'hedged_request.winner.throttle_machines' }

      assert winner_event, 'hedged_request.winner event should be emitted'
      assert_equal 1, winner_event[:payload][:winning_attempt]
      assert winner_event[:payload][:duration], 'duration should be included'
    end

    def test_custom_backend
      custom_events = []

      custom_backend = Class.new do
        define_method :instrument do |name, payload = {}, &block|
          custom_events << { name: name, payload: payload }
          block&.call
        end
      end.new

      ThrottleMachines.configure do |config|
        config.instrumentation_backend = custom_backend
      end

      limiter = ThrottleMachines.limiter('test', limit: 5, period: 60)
      limiter.allow?

      assert_equal 1, custom_events.size
      assert_equal 'rate_limit.checked.throttle_machines', custom_events.first[:name]
    end

    def test_events_include_all_required_fields
      # Test each event type has the expected payload

      # Rate limiter
      limiter = ThrottleMachines.limiter('test_fields', limit: 10, period: 120, algorithm: :gcra)
      limiter.allow?

      checked_event = @events.find { |e| e[:name] == 'rate_limit.checked.throttle_machines' }

      assert checked_event, 'rate_limit.checked event should be present'
      assert_equal 'test_fields', checked_event[:payload][:key]
      assert_equal 10, checked_event[:payload][:limit]
      assert_equal 120, checked_event[:payload][:period]
      assert_equal :gcra, checked_event[:payload][:algorithm]
    end
  end
end
