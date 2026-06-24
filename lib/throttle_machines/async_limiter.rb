# frozen_string_literal: true

module ThrottleMachines
  # Backward-compatible async-aware limiter class.
  #
  # Example:
  #   limiter = ThrottleMachines::AsyncLimiter.new("api",
  #     limit: 100,
  #     period: 60,
  #     algorithm: :gcra
  #   )
  #
  #   Async do
  #     if limiter.allowed_async?
  #       # Currently allowed without consuming capacity
  #     end
  #
  #     limiter.throttle_async(max_wait: 5) do
  #       # Consumes capacity through the same atomic path as throttle!
  #     end
  #   end
  class AsyncLimiter < Limiter
  end
end
