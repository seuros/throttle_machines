# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class LimiterTest < Test

    def test_basic_rate_limiting
      limiter = ThrottleMachines.limiter('test', limit: 5, period: 1)

      5.times do |i|
        assert_predicate limiter, :allow?, "Request #{i + 1} should be allowed"
        limiter.throttle! # Actually consume the request
      end

      assert_not_predicate limiter, :allow?
      assert_equal 0, limiter.remaining
    end

    def test_throttle_raises_error_when_limit_exceeded
      limiter = ThrottleMachines.limiter('test', limit: 1, period: 1)

      limiter.throttle! # First call succeeds

      assert_raises(ThrottledError) do
        limiter.throttle!
      end
    end

    def test_rate_limit_resets_after_period
      limiter = ThrottleMachines.limiter('test', limit: 1, period: 0.1)

      assert_predicate limiter, :allow?
      limiter.throttle! # Consume the request

      assert_not_predicate limiter, :allow?

      sleep 0.15

      assert_predicate limiter, :allow?
    end

    def test_unified_api
      call_count = 0
      error_count = 0

      5.times do
        ThrottleMachines.limit('api:test', limit: 3, period: 1) do
          call_count += 1
        end
      rescue ThrottledError
        error_count += 1
      end

      assert_equal 3, call_count
      assert_equal 2, error_count
    end
  end
end
