# frozen_string_literal: true

# Fiber-aware waiting for ThrottleMachines limiters.
#
# The async gem is optional. When an Async task is active, waits yield back to
# the scheduler; otherwise the limiter sleeps the thread.

module ThrottleMachines
  # Fiber-aware rate limiter helpers, included into Limiter.
  module AsyncSupport
    def allowed_async?
      allow?
    end

    def check_async
      return false unless allowed_async?

      yield if block_given?
      true
    end

    # Admits one call, waiting for the limiter while it throttles: at most
    # `max_wait` Integer nanoseconds (nil for no limit of its own), and never
    # past the ambient deadline_machines budget. Raises ThrottledError when
    # the next admission would come too late.
    def throttle_async(max_wait: nil, &block)
      caller_budget = DeadlineMachines.current

      DeadlineMachines.with_deadline(max_wait) do |budget|
        loop do
          begin
            throttle!
          rescue ThrottledError => e
            caller_budget&.check!
            wait = e.retry_after
            raise if budget.clamp_sleep(wait) < wait

            sleep_for(wait)
            next
          end

          return block ? block.call : true
        end
      end
    end

    private

    # Use Async's fiber-aware sleep when in an async context.
    def sleep_for(nanoseconds)
      seconds = Rational(nanoseconds, NS_PER_SECOND)
      if (task = current_async_task)
        task.sleep(seconds)
      else
        sleep(seconds)
      end
    end

    def current_async_task
      return nil unless defined?(::Async::Task)

      ::Async::Task.current?
    rescue StandardError
      nil
    end
  end
end

ThrottleMachines::Limiter.include(ThrottleMachines::AsyncSupport)
