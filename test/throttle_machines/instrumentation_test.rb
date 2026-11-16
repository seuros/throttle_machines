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

      limiter = ThrottleMachines.limiter('test_disabled', limit: 5, period: 60 * NS)
      limiter.allow?

      assert_empty @events, 'No events should be emitted when instrumentation is disabled'

      # Re-enable for other tests
      ThrottleMachines.configure do |config|
        config.instrumentation_enabled = true
      end
    end

    # Records every storage call a limiter makes.
    class StorageSpy < SimpleDelegator
      attr_reader :calls

      def initialize(storage)
        super
        @calls = []
      end

      %i[increment_counter get_counter get_counter_ttl check_gcra peek_gcra gcra_retry_after
         check_token_bucket peek_token_bucket token_bucket_retry_after].each do |name|
        define_method(name) do |*args|
          @calls << name
          __getobj__.public_send(name, *args)
        end
      end
    end

    CHECKS = { fixed_window: :increment_counter, gcra: :check_gcra, token_bucket: :check_token_bucket }.freeze
    RETRY_READS = { fixed_window: %i[get_counter get_counter_ttl], gcra: %i[gcra_retry_after],
                    token_bucket: %i[token_bucket_retry_after] }.freeze

    # Reproduces a bug: throttle! read `remaining` after an admission and
    # `retry_after` after a refusal for the event payload, one more storage
    # read per call even with instrumentation off.
    def test_throttle_reads_no_payload_from_storage_with_instrumentation_off
      ThrottleMachines.configure { |config| config.instrumentation_enabled = false }

      CHECKS.each do |algorithm, check|
        storage = StorageSpy.new(Storage::Memory.new(auto_cleanup: false))
        limiter = Limiter.new("spy-#{algorithm}", limit: 1, period: 60 * NS, algorithm: algorithm, storage: storage)

        limiter.throttle!
        assert_raises(ThrottledError) { limiter.throttle! }

        assert_equal [check, check], storage.calls, algorithm
      ensure
        storage&.shutdown
      end
      assert_empty @events
    ensure
      ThrottleMachines.configure { |config| config.instrumentation_enabled = true }
    end

    # An admission reports the count its check answered (equal to a fresh
    # `remaining`, see remaining_parity_test.rb); only a refusal reads
    # storage again, for `retry_after`.
    def test_throttle_reads_only_retry_after_with_instrumentation_on
      CHECKS.each do |algorithm, check|
        storage = StorageSpy.new(Storage::Memory.new(auto_cleanup: false))
        limiter = Limiter.new("spy-on-#{algorithm}", limit: 2, period: 60 * NS, algorithm: algorithm,
                                                    storage: storage)
        @events.clear

        admitted = algorithm == :gcra ? 1 : 2 # this GCRA has no burst
        admitted.times { limiter.throttle! }
        assert_raises(ThrottledError) { limiter.throttle! }

        assert_equal ([check] * (admitted + 1)) + RETRY_READS[algorithm], storage.calls, algorithm
        *allowed, throttled = @events.map { |e| e[:payload] }

        assert_equal (0...admitted).to_a.reverse, allowed.map { it[:remaining] }, algorithm
        assert_includes 1..(60 * NS), throttled[:retry_after], algorithm
      ensure
        storage&.shutdown
      end
    end

    def test_rate_limit_checked_event
      # Verify instrumentation is enabled
      assert ThrottleMachines::Instrumentation.enabled, 'Instrumentation should be enabled'

      limiter = ThrottleMachines.limiter('test', limit: 5, period: 60 * NS)
      allowed = limiter.allow?

      event = @events.find { |e| e[:name] == 'rate_limit.checked.throttle_machines' }

      assert event, 'rate_limit.checked event should be emitted'
      assert_equal 'test', event[:payload][:key]
      assert_equal 5, event[:payload][:limit]
      assert_equal 60 * NS, event[:payload][:period]
      assert_equal :fixed_window, event[:payload][:algorithm]
      assert_equal allowed, event[:payload][:allowed]
    end

    def test_rate_limit_allowed_event
      limiter = ThrottleMachines.limiter('test', limit: 5, period: 60 * NS)
      limiter.throttle! { 'work' }

      event = @events.find { |e| e[:name] == 'rate_limit.allowed.throttle_machines' }

      assert event, 'rate_limit.allowed event should be emitted'
      assert_equal 'test', event[:payload][:key]
      assert_equal 5, event[:payload][:limit]
      assert_equal 60 * NS, event[:payload][:period]
    end

    def test_rate_limit_throttled_event
      limiter = ThrottleMachines.limiter('test', limit: 1, period: 60 * NS)
      limiter.throttle! { 'first' }

      @events.clear # Clear previous events to focus on throttled event

      assert_raises(ThrottledError) do
        limiter.throttle! { 'second' }
      end

      event = @events.find { |e| e[:name] == 'rate_limit.throttled.throttle_machines' }

      assert event, 'rate_limit.throttled event should be emitted'
      assert_equal 'test', event[:payload][:key]
      assert_equal 1, event[:payload][:limit]
      assert_equal 60 * NS, event[:payload][:period]
      assert event[:payload][:retry_after], 'retry_after should be included'
    end

    def test_hedged_request_events
      hedged = HedgedRequest.new(delay: 10 * MS, max_attempts: 2)
      release = Queue.new

      result = hedged.run do |attempt|
        case attempt
        when 0
          release.pop
          'slow'
        when 1
          'fast'
        end
      end
      release << true
      hedged.shutdown

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

      limiter = ThrottleMachines.limiter('test', limit: 5, period: 60 * NS)
      limiter.allow?

      assert_equal 1, custom_events.size
      assert_equal 'rate_limit.checked.throttle_machines', custom_events.first[:name]
    end

    def test_events_include_all_required_fields
      # Test each event type has the expected payload

      # Rate limiter
      limiter = ThrottleMachines.limiter('test_fields', limit: 10, period: 120 * NS, algorithm: :gcra)
      limiter.allow?

      checked_event = @events.find { |e| e[:name] == 'rate_limit.checked.throttle_machines' }

      assert checked_event, 'rate_limit.checked event should be present'
      assert_equal 'test_fields', checked_event[:payload][:key]
      assert_equal 10, checked_event[:payload][:limit]
      assert_equal 120 * NS, checked_event[:payload][:period]
      assert_equal :gcra, checked_event[:payload][:algorithm]
    end
  end
end
