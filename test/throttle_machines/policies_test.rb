# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  # The policy Data values: validated through the core however they are
  # built, sealed, and read natively only by exact class.
  class PoliciesTest < Minitest::Test
    def test_a_gcra_policy_holds_its_spans_in_nanoseconds
      policy = GcraPolicy.new(100 * MS, 200 * MS)

      assert_equal [100 * MS, 200 * MS], [policy.emission_interval, policy.delay_tolerance]
      assert_predicate policy, :frozen?
      assert_equal policy, GcraPolicy.new(emission_interval: 100 * MS, delay_tolerance: 200 * MS)
    end

    def test_gcra_per_spreads_the_limit_and_rounds_the_interval_up
      assert_equal GcraPolicy.new(100 * MS, 200 * MS), GcraPolicy.per(NS, 10, 3)
      assert_equal GcraPolicy.new(4, 0), GcraPolicy.per(10, 3, 1)
    end

    def test_token_bucket_per_holds_the_limit_and_spreads_the_refill
      assert_equal TokenBucketPolicy.new(3, 333_333_334), TokenBucketPolicy.per(NS, 3)
    end

    def test_a_value_the_core_refuses_is_a_range_error
      assert_raises(RangeError) { GcraPolicy.new(0, 0) }
      assert_raises(RangeError) { GcraPolicy.new(-1, 0) }
      assert_raises(RangeError) { GcraPolicy.new(1, 2**64) }
      assert_raises(RangeError) { TokenBucketPolicy.new(0, NS) }
      assert_raises(RangeError) { TokenBucketPolicy.new(1, 0) }
      assert_raises(RangeError) { FixedWindowPolicy.new(0, 1) }
      assert_raises(RangeError) { FixedWindowPolicy.new(NS, 0) }
      assert_raises(RangeError) { GcraPolicy.per(0, 1, 1) }
      assert_raises(RangeError) { GcraPolicy.per(NS, 0, 1) }
      assert_raises(RangeError) { GcraPolicy.per(2**64 - 1, 1, 2**63) }
      assert_raises(RangeError) { TokenBucketPolicy.per(NS, 0) }
    end

    # Was: a capacity of 2**64 (one interval of 1 ns, 2**64-1 ns tolerated)
    # was accepted and its gate answered 2**64-1.
    def test_a_gcra_capacity_past_two_to_the_64_is_a_range_error
      assert_raises(RangeError) { GcraPolicy.new(1, (2**64) - 1) }

      widest = Gcra.new(GcraPolicy.new(1, (2**64) - 2))

      assert_equal (2**64) - 1, widest.peek(0)
      assert_equal (2**64) - 2, widest.check(0)
    end

    def test_a_value_of_the_wrong_type_is_a_type_error
      assert_raises(TypeError) { GcraPolicy.new(0.5, 0) }
      assert_raises(TypeError) { GcraPolicy.new(NS, nil) }
      assert_raises(TypeError) { TokenBucketPolicy.new('3', NS) }
      assert_raises(TypeError) { FixedWindowPolicy.new(NS, 1.0) }
      assert_raises(TypeError) { GcraPolicy.per(1.0, 1, 1) }
    end

    def test_the_values_are_sealed
      [GcraPolicy, TokenBucketPolicy, FixedWindowPolicy].each do |value|
        assert_raises(NoMethodError) { value.allocate }
        assert_raises(TypeError) { Class.new(value) }
      end
    end

    def test_the_validation_hooks_are_private
      %i[__gcra_policy __token_bucket_policy __fixed_window_policy __gcra_per __token_bucket_per].each do |hook|
        assert_raises(NoMethodError) { ThrottleMachines.public_send(hook) }
      end
    end

    def test_a_gate_reads_only_its_exact_policy_class
      forged = Data.define(:emission_interval, :delay_tolerance).new(NS, 0)

      assert_raises(TypeError) { Gcra.new(forged) }
      assert_raises(TypeError) { Gcra.new(TokenBucketPolicy.new(1, NS)) }
      assert_raises(TypeError) { TokenBucket.new(GcraPolicy.new(NS, 0)) }
      assert_raises(TypeError) { FixedWindow.new(nil) }
    end

    def test_a_gate_checks_the_fields_again_and_ignores_redefined_readers
      # Marshal.load skips initialize: a zero interval the core refuses.
      forged = Marshal.load(Marshal.dump(GcraPolicy.new(1, 0)).sub("i\x06", "i\x00"))

      assert_equal 0, forged.emission_interval
      assert_raises(RangeError) { Gcra.new(forged) }

      policy = GcraPolicy.new(NS, 0)
      GcraPolicy.alias_method(:honest_interval, :emission_interval)
      GcraPolicy.define_method(:emission_interval) { 0 }

      assert_equal NS, Gcra.new(policy).policy.honest_interval
    ensure
      GcraPolicy.alias_method(:emission_interval, :honest_interval)
    end

    def test_gates_still_build_after_gc_compact
      GC.compact

      assert_equal 0, Gcra.new(GcraPolicy.new(NS, 0)).check(NS)
      assert_equal FixedWindowPolicy.new(NS, 1), FixedWindow.new(FixedWindowPolicy.new(NS, 1)).policy
    end
  end
end
