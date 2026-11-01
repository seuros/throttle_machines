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

    # A reset belongs to one limiter: not to a neighbour whose key it prefixes,
    # and not to whatever its metacharacters would match as a pattern.
    CONFINEMENT_KEYS = %w[account:1 account:10 a.c abc].freeze

    %i[fixed_window gcra token_bucket].each do |algorithm|
      define_method("test_#{algorithm}_reset_is_confined_to_its_own_limiter") do
        storage = Storage::Memory.new(auto_cleanup: false)
        limiters = CONFINEMENT_KEYS.to_h do |key|
          limiter = Limiter.new(key, limit: 1, period: 600, algorithm: algorithm, storage: storage)
          limiter.throttle!
          [key, limiter]
        end
        limiters.each { |key, limiter| assert_not_predicate limiter, :allow?, key }

        limiters['account:1'].reset!

        assert_predicate limiters['account:1'], :allow?
        assert_not_predicate limiters['account:10'], :allow?

        limiters['a.c'].reset!

        assert_predicate limiters['a.c'], :allow?
        assert_not_predicate limiters['abc'], :allow?
      end
    end

    def test_global_reset_of_a_key_spares_a_key_it_prefixes
      pacer = ThrottleMachines.limiter('account:1', limit: 1, period: 600, algorithm: :gcra)
      neighbour = ThrottleMachines.limiter('account:10', limit: 1, period: 600, algorithm: :gcra)
      counter = ThrottleMachines.limiter('account:1', limit: 1, period: 600)
      [pacer, neighbour, counter].each(&:throttle!)

      ThrottleMachines.reset!('account:1')

      assert_predicate pacer, :allow?
      assert_predicate counter, :allow?
      assert_not_predicate neighbour, :allow?
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
