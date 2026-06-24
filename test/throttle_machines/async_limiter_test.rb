# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class AsyncLimiterTest < Test
    def test_regular_limiters_expose_async_api
      limiter = ThrottleMachines.limiter('async:regular', limit: 1, period: 60)

      assert_respond_to limiter, :allowed_async?
      assert_respond_to limiter, :throttle_async
    end

    def test_throttle_async_consumes_fixed_window_quota
      limiter = AsyncLimiter.new('async:fixed', limit: 1, period: 60)

      assert_equal :first, limiter.throttle_async { :first }

      assert_raises(ThrottledError) do
        limiter.throttle_async(max_wait: 0) { :second }
      end
    end

    def test_throttle_async_uses_shared_token_bucket_storage
      first = AsyncLimiter.new('async:token', limit: 1, period: 60, algorithm: :token_bucket)
      second = AsyncLimiter.new('async:token', limit: 1, period: 60, algorithm: :token_bucket)

      assert_equal true, first.throttle_async

      assert_raises(ThrottledError) do
        second.throttle_async(max_wait: 0)
      end
    end

    def test_allowed_async_is_non_consuming
      limiter = AsyncLimiter.new('async:allowed', limit: 1, period: 60)

      assert_predicate limiter, :allowed_async?
      assert_predicate limiter, :allowed_async?
      assert_equal true, limiter.throttle_async

      assert_raises(ThrottledError) do
        limiter.throttle_async(max_wait: 0)
      end
    end

    def test_check_async_yields_only_when_currently_allowed
      limiter = AsyncLimiter.new('async:check', limit: 1, period: 60)
      yielded = false

      assert_equal true, limiter.check_async { yielded = true }
      assert_equal true, yielded

      limiter.throttle_async

      assert_equal false, limiter.check_async
    end

    def test_throttle_async_uses_active_async_task_sleep
      skip 'Async constant already loaded' if defined?(::Async)

      limiter = AsyncLimiter.new('async:sleep', limit: 1, period: 60)
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

      assert_equal :after_wait, limiter.throttle_async(max_wait: 60) { :after_wait }
      assert_equal 1, sleeps.size
      assert_operator sleeps.first, :>, 0
    ensure
      Object.send(:remove_const, :Async) if defined?(::Async) && async_module
    end

    def test_async_enabled_aliases_fiber_safe
      ThrottleMachines.config.async_enabled = false

      assert_equal false, ThrottleMachines.config.fiber_safe
      assert_equal false, ThrottleMachines.config.async_enabled
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
        ThrottleMachines::AsyncBreaker.new('async:breaker', failure_threshold: 1, reset_timeout: 1)
      end

      assert_match(/async/, error.message)
    end
  end
end
