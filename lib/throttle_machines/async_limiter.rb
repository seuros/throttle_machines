# frozen_string_literal: true

require 'concurrent-ruby'

module ThrottleMachines
  # Async-aware rate limiter for fiber-safe operations
  #
  # Like quantum entanglement communications - allows multiple spacecraft
  # to communicate simultaneously without interference, each in their own
  # quantum state (fiber).
  #
  # Example:
  #   limiter = ThrottleMachines::AsyncLimiter.new("quantum_comms",
  #     limit: 100,
  #     period: 60,
  #     algorithm: :gcra
  #   )
  #
  #   Async do
  #     if limiter.allowed_async?
  #       # Non-blocking operation
  #     end
  #   end
  class AsyncLimiter < Limiter
    def initialize(key, limit:, period:, algorithm: :fixed_window, storage: nil)
      super
      @fiber_storage = Concurrent::Map.new # Thread-safe fiber storage
    end

    # Async version of allowed? that's fiber-safe
    def allowed_async?
      allowed = if defined?(Async::Task) && Async::Task.current?
                  # In async context, use fiber-local checking
                  fiber_allowed?
                else
                  # Fall back to regular synchronous check
                  allowed?
                end

      # Don't double-instrument when calling parent allowed?
      return allowed unless defined?(Async::Task) && Async::Task.current?

      # Instrument the async check
      Instrumentation.rate_limit_checked(self, allowed: allowed, remaining: nil)
      allowed
    end

    # Non-blocking check with async support
    def check_async
      if allowed_async?
        yield if block_given?
        true
      else
        false
      end
    end

    # Async throttle with automatic retry
    def throttle_async(max_wait: nil)
      start_time = current_time

      loop do
        if allowed_async?
          return yield if block_given?

          return true
        end

        wait_time = retry_after

        # Check if we've exceeded max wait time
        if max_wait && (current_time - start_time + wait_time) > max_wait
          raise ThrottleError, 'Maximum wait time exceeded'
        end

        # Non-blocking sleep in async context
        if defined?(Async::Task) && Async::Task.current?
          Async::Task.current.sleep(wait_time)
        else
          sleep(wait_time)
        end
      end
    end

    # Get current fiber's state
    def fiber_state
      fiber_id = Fiber.current.object_id
      @fiber_storage.compute_if_absent(fiber_id) do
        {
          last_check: 0,
          tokens: @limit.to_f
        }
      end
    end

    # Clean up fiber storage periodically
    def cleanup_fiber_storage
      current_fibers = ObjectSpace.each_object(Fiber).map(&:object_id)
      @fiber_storage.each_key do |fiber_id|
        @fiber_storage.delete(fiber_id) unless current_fibers.include?(fiber_id)
      end
    end

    private

    def fiber_allowed?
      state = fiber_state
      now = current_time

      case @algorithm
      when :token_bucket
        # Refill tokens based on time passed
        time_passed = now - state[:last_check]
        tokens_to_add = time_passed * (@limit.to_f / @period)
        state[:tokens] = [state[:tokens] + tokens_to_add, @limit.to_f].min
        state[:last_check] = now

        if state[:tokens] >= 1
          state[:tokens] -= 1
          true
        else
          false
        end
      else
        # Delegate to parent for other algorithms
        allowed?
      end
    end

    def current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
