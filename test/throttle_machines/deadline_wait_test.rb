# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class DeadlineWaitTest < Minitest::Test
    def setup
      @clock = DeadlineMachines::TestClock.new
      DeadlineMachines.clock = @clock
      ThrottleMachines.reset!
      @limiter = ThrottleMachines.limiter('deadline-wait', limit: 1, period: 60)
      @limiter.throttle!
    end

    def teardown
      DeadlineMachines.clock = nil
      ThrottleMachines.reset!
    end

    def test_an_abandoned_caller_stops_waiting_for_a_slot
      DeadlineMachines.with_deadline(5) do |deadline|
        deadline.cancel('client hung up')

        assert_raises(DeadlineMachines::Cancelled) do
          @limiter.throttle_async(max_wait: 120) { :never }
        end
      end
    end

    def test_the_ambient_budget_bounds_the_wait_when_no_max_wait_is_given
      assert_raises(ThrottledError) do
        DeadlineMachines.with_deadline(1) { @limiter.throttle_async { :never } }
      end
    end
  end
end
