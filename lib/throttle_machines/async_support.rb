# frozen_string_literal: true

# Async/Fiber support for ThrottleMachines.
#
# This module is automatically loaded when the Async gem is available.
# It prepends fiber-aware sleep onto Limiter for cooperative scheduling.

return unless defined?(Async)

module ThrottleMachines
  # Fiber-aware sleep support for rate limiting.
  module AsyncSupport
    private

    # Override sleep to use Async's fiber-aware sleep when in an async context.
    def sleep_for(duration)
      task = begin
        Async::Task.current
      rescue StandardError
        nil
      end

      if task
        task.sleep(duration)
      else
        super
      end
    end
  end
end

ThrottleMachines::Limiter.prepend(ThrottleMachines::AsyncSupport)

warn "[ThrottleMachines] Async support loaded" if ENV["DEBUG_MATRYOSHKA"]
