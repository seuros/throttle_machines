# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class NativeTest < Test
    def setup
      skip 'Native extension not available' unless defined?(::ThrottleMachinesNative)
    end

    def test_checks_return_frozen_decisions
      decision = ::ThrottleMachinesNative.gcra_check(0.0, 10.0, 1.0, 0.0)

      assert_kind_of ::ThrottleMachinesNative::Decision, decision
      assert_predicate decision, :frozen?
      assert decision.allowed
      assert_in_delta 11.0, decision.state
      assert_in_delta 0.0, decision.retry_after
    end

    def test_decisions_destructure_by_member
      ::ThrottleMachinesNative.token_bucket_check(5.0, 0.0, 0.0, 5.0, 1.0) =>
        { allowed:, state: tokens, retry_after: }

      assert allowed
      assert_in_delta 4.0, tokens
      assert_in_delta 0.0, retry_after
    end

    def test_breaker_record_returns_an_outcome
      outcome = ::ThrottleMachinesNative.circuit_breaker_record(0, 0, 5.0, false, 1)

      assert_kind_of ::ThrottleMachinesNative::Outcome, outcome
      assert_equal 1, outcome.state
      assert_equal 1, outcome.failures
      assert_in_delta 5.0, outcome.opened_at
    end

    def test_runs_inside_a_ractor_and_returns_shareable_results
      experimental = Warning[:experimental]
      Warning[:experimental] = false

      decision = Ractor.new { ::ThrottleMachinesNative.gcra_check(0.0, 10.0, 1.0, 0.0) }.value

      assert Ractor.shareable?(decision)
      assert decision.allowed
    ensure
      Warning[:experimental] = experimental
    end
  end
end
