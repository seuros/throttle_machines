# frozen_string_literal: true

module ThrottleMachines
  # TestClock for time manipulation in tests
  # This overrides the global monotonic_time method for testing
  class TestClock
    attr_accessor :current_time

    def initialize(start_time = Time.now.to_f)
      @current_time = start_time
      
      # Override the global monotonic_time method
      ThrottleMachines.singleton_class.define_method(:monotonic_time) do
        @current_time
      end
    end

    def now
      @current_time
    end

    def monotonic
      @current_time
    end

    def advance(seconds)
      @current_time += seconds
    end

    def travel_to(time)
      @current_time = time.to_f
    end

    def reset
      # Restore the original monotonic_time method
      ThrottleMachines.singleton_class.define_method(:monotonic_time) do
        BreakerMachines.monotonic_time
      end
    end
  end
end
