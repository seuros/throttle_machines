# frozen_string_literal: true

# Async/Fiber support for ThrottleMachines.
#
# The async gem is optional. When an Async task is active, waits yield back to
# the scheduler; otherwise the limiter falls back to normal sleep.

module ThrottleMachines
  # Fiber-aware rate limiter helpers.
  module AsyncSupport
    def allowed_async?
      allow?
    end

    alias allow_async? allowed_async?

    def check_async
      return false unless allowed_async?

      yield if block_given?
      true
    end

    def throttle_async(max_wait: nil, &block)
      deadline = max_wait.nil? ? nil : ThrottleMachines.monotonic_time + max_wait.to_f

      loop do
        begin
          throttle!
        rescue ThrottledError => e
          wait_time = [e.retry_after.to_f, 0.0].max

          if deadline
            remaining_wait = deadline - ThrottleMachines.monotonic_time
            raise if remaining_wait <= 0 || wait_time > remaining_wait
          end

          sleep_for(wait_time)
          next
        end

        return block.call if block

        return true
      end
    end

    private

    # Use Async's fiber-aware sleep when in an async context.
    def sleep_for(duration)
      if (task = current_async_task)
        task.sleep(duration)
      else
        sleep(duration)
      end
    end

    def current_async_task
      return nil unless defined?(::Async::Task)

      if ::Async::Task.respond_to?(:current?)
        ::Async::Task.current?
      else
        ::Async::Task.current
      end
    rescue StandardError
      nil
    end
  end
end

ThrottleMachines::Limiter.include(ThrottleMachines::AsyncSupport)

warn "[ThrottleMachines] Async support loaded" if ENV['DEBUG_MATRYOSHKA']
