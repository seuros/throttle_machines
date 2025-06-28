# frozen_string_literal: true

module ThrottleMachines
  class ThrottledError < StandardError
    attr_reader :limiter

    def initialize(limiter)
      @limiter = limiter
      super("Rate limit exceeded for #{limiter.key}")
    end

    delegate :retry_after, to: :@limiter
  end
end
