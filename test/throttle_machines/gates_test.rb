# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  # The native gates mirror the core's: `check` answers the calls still
  # admitted or :throttled, which changes nothing; every span is Integer
  # nanoseconds.
  class GatesTest < Minitest::Test
    NOW = 5 * NS
    # The last instant a Duration holds, in nanoseconds.
    DURATION_MAX = ((2**64) * NS) - 1

    def gcra = Gcra.new(GcraPolicy.per(NS, 10, 3))
    def bucket = TokenBucket.new(TokenBucketPolicy.new(2, NS))
    def window = FixedWindow.new(FixedWindowPolicy.new(60 * NS, 2))

    def test_gcra_admits_a_burst_then_throttles_without_moving_the_tat
      gate = gcra

      assert_equal 3, gate.peek(NOW)
      assert_equal [2, 1, 0], Array.new(3) { gate.check(NOW) }
      tat = gate.tat

      assert_equal :throttled, gate.check(NOW)
      assert_equal tat, gate.tat
      assert_equal :throttled, gate.peek(NOW)
      assert_equal 100 * MS, gate.retry_after(NOW)
      assert_equal 0, gate.check(NOW + (100 * MS))
    end

    def test_gcra_refund_and_restore
      gate = gcra
      gate.check(NOW)

      assert_equal NOW + (100 * MS), gate.tat
      assert_nil gate.refund
      assert_equal NOW, gate.tat

      restored = Gcra.restored(gate.policy, NOW + (300 * MS))

      assert_equal :throttled, restored.check(NOW)
      assert_equal GcraPolicy.per(NS, 10, 3), restored.policy
    end

    def test_token_bucket_spends_and_refills_whole_tokens
      gate = bucket

      assert_equal 2, gate.tokens
      assert_equal [1, 0, :throttled], Array.new(3) { gate.check(NOW) }
      assert_equal NOW, gate.refilled_at
      assert_equal NS, gate.retry_after(NOW)
      assert_equal 1, gate.peek(NOW + NS)
      assert_nil gate.refund
      assert_equal 1, gate.tokens
      assert_equal TokenBucketPolicy.new(2, NS), gate.policy
    end

    def test_token_bucket_restored_refuses_more_than_capacity
      policy = TokenBucketPolicy.new(2, NS)

      assert_raises(RangeError) { TokenBucket.restored(policy, 3, 0) }
      assert_raises(TypeError) { TokenBucket.restored(policy, 1.0, 0) }
      assert_equal :throttled, TokenBucket.restored(policy, 0, NOW).check(NOW)
    end

    def test_fixed_window_counts_to_its_limit_and_reopens
      gate = window

      assert_equal [1, 0, :throttled], Array.new(3) { gate.check(70 * NS) }
      assert_equal 2, gate.count
      assert_equal 70 * NS, gate.window_start
      assert_equal 50 * NS, gate.retry_after(80 * NS)
      assert_equal 2, gate.peek(130 * NS)
      assert_nil gate.refund
      assert_equal 1, gate.count
      assert_equal FixedWindowPolicy.new(60 * NS, 2), gate.policy
    end

    def test_fixed_window_restored_refuses_a_count_past_the_limit
      policy = FixedWindowPolicy.new(NS, 1)

      assert_raises(RangeError) { FixedWindow.restored(policy, 2, 0) }
      assert_equal :throttled, FixedWindow.restored(policy, 1, NOW).peek(NOW)
    end

    def test_every_now_is_integer_nanoseconds
      [gcra, bucket, window].each do |gate|
        assert_raises(TypeError) { gate.check(1.5) }
        assert_raises(RangeError) { gate.check(-1) }
        assert_raises(RangeError) { gate.peek(DURATION_MAX + 1) }
        assert_raises(TypeError) { gate.retry_after(nil) }
      end
      assert_raises(RangeError) { Gcra.restored(GcraPolicy.new(NS, 0), -1) }
    end

    # Was: `now` was read as a u64, so a TAT past 2**64-1 could not be
    # handed back: peek(tat) raised RangeError.
    def test_every_tat_reads_back_as_now
      gate = Gcra.new(GcraPolicy.new(1, 0))

      assert_equal 0, gate.check((2**64) - 1)
      assert_equal 2**64, gate.tat
      assert_equal 1, gate.peek(gate.tat)
      assert_equal 0, gate.retry_after(gate.tat)
      assert_equal 0, gate.check(gate.tat)
    end

    def test_every_gate_reads_now_over_the_whole_duration_range
      assert_equal [:overflow, 2, 2], [gcra, bucket, window].map { |gate| gate.peek(DURATION_MAX) }
      assert_equal [DURATION_MAX, 0, 0], [gcra, bucket, window].map { |gate| gate.retry_after(DURATION_MAX) }
    end

    # Was: the TAT saturated at the end of time, which put it back within
    # tolerance, so every later check at that instant was admitted.
    def test_a_tat_past_the_end_of_time_refuses_as_overflow
      gate = Gcra.new(GcraPolicy.new(NS, 1500 * MS))
      now = DURATION_MAX - (1200 * MS)

      assert_equal 1, gate.peek(now)
      assert_equal 0, gate.check(now)
      tat = gate.tat

      assert_equal :overflow, gate.check(now)
      assert_equal tat, gate.tat
      assert_equal :overflow, gate.peek(now)
      assert_equal DURATION_MAX, gate.retry_after(now)
    end

    def test_a_frozen_gate_refuses_to_change_before_reading_its_arguments
      [gcra, bucket, window].each do |gate|
        gate.freeze

        assert_raises(FrozenError) { gate.check(:not_a_time) }
        assert_raises(FrozenError) { gate.refund }
        assert_equal 0, gate.retry_after(NOW)
      end
    end

    def test_gates_cannot_be_allocated_or_copied
      [Gcra, TokenBucket, FixedWindow].each do |klass|
        assert_raises(TypeError, NoMethodError) { klass.allocate }
      end
      assert_raises(TypeError) { gcra.dup }
    end
  end
end
