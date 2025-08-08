# frozen_string_literal: true

module ThrottleMachines
  # Hedged request with circuit breaker integration
  class HedgedBreaker
    def initialize(breakers, delay: 0.05)
      @breakers = Array(breakers)
      @hedged = HedgedRequest.new(
        delay: delay,
        max_attempts: @breakers.size
      )
    end

    def run(&)
      @hedged.run do |attempt|
        breaker = @breakers[attempt]
        next if breaker.nil?

        breaker.call(&)
      end
    end
  end
end
