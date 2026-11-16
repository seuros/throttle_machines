# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class AsyncSupportTest < Test
    def test_regular_limiters_expose_async_api
      limiter = ThrottleMachines.limiter('async:regular', limit: 1, period: 60 * NS)

      assert_respond_to limiter, :allowed_async?
      assert_respond_to limiter, :throttle_async
    end

    def test_throttle_async_consumes_fixed_window_quota
      limiter = ThrottleMachines.limiter('async:fixed', limit: 1, period: 60 * NS)

      assert_equal :first, limiter.throttle_async { :first }

      assert_raises(ThrottledError) do
        limiter.throttle_async(max_wait: 0) { :second }
      end
    end

    def test_throttle_async_uses_shared_token_bucket_storage
      first = ThrottleMachines.limiter('async:token', limit: 1, period: 60 * NS, algorithm: :token_bucket)
      second = ThrottleMachines.limiter('async:token', limit: 1, period: 60 * NS, algorithm: :token_bucket)

      assert_equal true, first.throttle_async

      assert_raises(ThrottledError) do
        second.throttle_async(max_wait: 0)
      end
    end

    def test_allowed_async_is_non_consuming
      limiter = ThrottleMachines.limiter('async:allowed', limit: 1, period: 60 * NS)

      assert_predicate limiter, :allowed_async?
      assert_predicate limiter, :allowed_async?
      assert_equal true, limiter.throttle_async

      assert_raises(ThrottledError) do
        limiter.throttle_async(max_wait: 0)
      end
    end

    def test_check_async_yields_only_when_currently_allowed
      limiter = ThrottleMachines.limiter('async:check', limit: 1, period: 60 * NS)
      yielded = false

      assert_equal true, limiter.check_async { yielded = true }
      assert_equal true, yielded

      limiter.throttle_async

      assert_equal false, limiter.check_async
    end

    def test_throttle_async_uses_active_async_task_sleep
      skip 'Async constant already loaded' if defined?(::Async)

      limiter = ThrottleMachines.limiter('async:sleep', limit: 1, period: 60 * NS)
      sleeps = []
      fake_task = Object.new

      fake_task.define_singleton_method(:sleep) do |duration|
        sleeps << duration
        limiter.reset!
      end

      task_class = Class.new
      task_class.define_singleton_method(:current?) { fake_task }

      async_module = Module.new
      async_module.const_set(:Task, task_class)
      Object.const_set(:Async, async_module)

      limiter.throttle_async

      assert_equal :after_wait, limiter.throttle_async(max_wait: 60 * NS) { :after_wait }
      assert_equal 1, sleeps.size
      assert_operator sleeps.first, :>, 0
    ensure
      Object.send(:remove_const, :Async) if defined?(::Async) && async_module
    end

    def test_the_wait_sleeps_the_retry_after_as_exact_seconds
      skip 'Async constant already loaded' if defined?(::Async)

      clock = TestClock.new
      limiter = ThrottleMachines.limiter('async:exact', limit: 1, period: 3 * NS, algorithm: :gcra)
      limiter.throttle!
      slept = []
      fake_task = Object.new
      fake_task.define_singleton_method(:sleep) do |seconds|
        slept << seconds
        clock.advance(3 * NS)
      end
      task_class = Class.new
      task_class.define_singleton_method(:current?) { fake_task }
      async_module = Module.new
      async_module.const_set(:Task, task_class)
      Object.const_set(:Async, async_module)

      assert_equal :done, limiter.throttle_async(max_wait: 10 * NS) { :done }
      assert_equal [Rational(3)], slept
    ensure
      clock&.reset
      Object.send(:remove_const, :Async) if defined?(::Async) && async_module
    end

    def test_fiber_safe_mode_requires_async_gem
      require 'async'
      skip 'async gem is available in this bundle'
    rescue LoadError
      error = assert_raises(LoadError) do
        ThrottleMachines.config.fiber_safe = true
      end

      assert_match(/async/, error.message)
    ensure
      ThrottleMachines.config.fiber_safe = false
    end

    def test_async_breaker_requires_async_gem
      require 'async'
      skip 'async gem is available in this bundle'
    rescue LoadError
      error = assert_raises(LoadError) do
        ThrottleMachines::AsyncBreaker.new('async:breaker', Breakers.policy(1, NS, NS))
      end

      assert_match(/async/, error.message)
    end
  end
end
