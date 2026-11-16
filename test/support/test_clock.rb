# frozen_string_literal: true

module ThrottleMachines
  # Stands in for ThrottleMachines.monotonic_time: Integer nanoseconds that
  # move only when a test moves them.
  class TestClock
    attr_reader :now

    def initialize(start = 1_000 * NS_PER_SECOND)
      @now = start
      @original = ThrottleMachines.method(:monotonic_time)
      clock = self
      ThrottleMachines.singleton_class.define_method(:monotonic_time) { clock.now }
    end

    def advance(nanoseconds)
      @now += nanoseconds
    end

    def travel_to(nanoseconds)
      @now = nanoseconds
    end

    def reset
      ThrottleMachines.singleton_class.define_method(:monotonic_time, @original)
    end
  end
end
