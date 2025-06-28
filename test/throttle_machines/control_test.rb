# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class ControlTest < Test

    def test_control_with_all_features
      # Test rate limiting
      control = ThrottleMachines.control('test:rate') do
        limit rate: 2, per: 60, algorithm: :fixed_window
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
        break_on failures: 2, within: 60
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
        retry_on_failure times: 2, base_delay: 0.01
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

    def test_control_with_only_rate_limiting
      control = ThrottleMachines.control('rate:only') do
        limit rate: 2, per: 1, algorithm: :fixed_window
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
  end
end
