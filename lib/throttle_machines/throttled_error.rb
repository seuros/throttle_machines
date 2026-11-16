# frozen_string_literal: true

module ThrottleMachines
  class ThrottledError < StandardError
    attr_reader :limiter

    def initialize(limiter)
      @limiter = limiter
      super("Rate limit exceeded for #{limiter.key}")
    end

    # Integer nanoseconds until the limiter admits a call, asked now.
    def retry_after
      @limiter.retry_after
    end
  end
end
