# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class ControlTest < Test
    def test_control_with_all_features
      # Test rate limiting
      control = ThrottleMachines.control('test:rate') do
        limit rate: 2, per: 60 * NS, algorithm: :fixed_window
      end

      # Make two successful calls
      results = []
      2.times { control.call { results << 'ok' } }

      assert_equal %w[ok ok], results

      # Third call should be throttled
      assert_raises(ThrottledError) do
        control.call { results << 'should not happen' }
      end

      # Test circuit breaker
      ThrottleMachines.reset!
      control2 = ThrottleMachines.control('test:breaker') do
        break_on failures: 2, within: 60 * NS
      end

      # Cause two failures to trip the breaker
      2.times do |i|
        assert_raises(RuntimeError) do
          control2.call { raise "Error #{i}" }
        end
      end

      # Next call should fail with circuit open
      assert_raises(BreakerMachines::CircuitOpenError) do
        control2.call { 'should not execute' }
      end

      # Test retry with non-rate-limited error
      control3 = ThrottleMachines.control('test:retry') do
        retry_on_failure ChronoMachines::Constant.new(MS, 0.0), 2
      end

      attempts = 0
      assert_raises(ChronoMachines::MaxRetriesExceededError) do
        control3.call do
          attempts += 1
          raise Timeout::Error, 'Simulated timeout'
        end
      end
      assert_equal 2, attempts
    end

    # Reproduces a bug: the limiter runs inside the breaker, so every
    # ThrottledError counted as a breaker failure and tripped it.
    def test_being_throttled_does_not_trip_the_breaker
      control = ThrottleMachines.control('test:throttled') do
        limit rate: 1, per: 60 * NS, algorithm: :fixed_window
        break_on failures: 2, within: 60 * NS
      end

      assert_equal :ok, control.call { :ok }
      3.times { assert_raises(ThrottledError) { control.call { :never } } }

      assert_predicate control.breaker, :closed?
      assert_equal 0, control.breaker.stats.failure_count
    end

    def test_control_with_only_rate_limiting
      control = ThrottleMachines.control('rate:only') do
        limit rate: 2, per: NS, algorithm: :fixed_window
      end

      results = []
      3.times do |i|
        control.call { results << i }
      rescue ThrottledError
        results << :throttled
      end

      # With atomic increment, the first request increments to 1, second to 2, third exceeds
      assert_equal [0, 1, :throttled], results
    end

    def test_retries_follow_the_chrono_shape_and_its_runtime_keywords
      delays = []
      control = ThrottleMachines.control('test:shape') do
        retry_on_failure ChronoMachines::Exponential.new(MS, 2.0, 4 * MS, 0.0), 3,
                         on_retry: ->(next_delay:, **) { delays << next_delay }
      end

      attempts = 0
      result = control.call do
        attempts += 1
        raise IOError, 'flaky' if attempts < 3

        :recovered
      end

      assert_equal :recovered, result
      assert_equal [MS, 2 * MS], delays
    end

    def test_retry_with_delegates_to_chrono_machines
      attempts = 0
      assert_raises(ChronoMachines::MaxRetriesExceededError) do
        ThrottleMachines.retry_with(ChronoMachines::Constant.new(MS, 0.0), 2) do
          attempts += 1
          raise IOError, 'down'
        end
      end
      assert_equal 2, attempts
    end
  end
end
