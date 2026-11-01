# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  # Whichever backend is loaded answers the same, by value and by class, so a
  # caller cannot tell which one decided. The suite runs under both, so pinning
  # one sequence here is what keeps them from drifting apart.
  class BackendParityTest < Minitest::Test
    # A synthetic clock, so a decision depends only on the sequence.
    EPOCH = 1_000_000.0

    # The step between calls, small enough to exhaust the allowance.
    STEP = 0.02

    BUCKET = [[true, 0.0, "Float", 4], [true, 0.0, "Float", 3], [true, 0.0, "Float", 2], [true, 0.0, "Float", 1], [true, 0.0, "Float", 0], [true, 0.0, "Float", 0], [false, 0.08, "Float", 0], [false, 0.06, "Float", 0], [false, 0.04, "Float", 0], [false, 0.02, "Float", 0], [true, 0.0, "Float", 0], [false, 0.08, "Float", 0]].freeze

    GCRA = [[true, 0.0, "Float"], [true, 0.0, "Float"], [true, 0.0, "Float"], [true, 0.0, "Float"], [false, 0.02, "Float"], [true, 0.0, "Float"], [false, 0.03, "Float"], [false, 0.01, "Float"], [true, 0.0, "Float"], [false, 0.02, "Float"], [true, 0.0, "Float"], [false, 0.03, "Float"]].freeze

    def setup
      @store = Storage::Memory.new(auto_cleanup: false)
    end

    def teardown
      @store.shutdown
    end

    def test_the_token_bucket_answers_what_both_backends_answer
      answers = walk do |now|
        decision = @store.check_token_bucket('parity', 5, 10.0, 60)
        [decision[:allowed], decision[:retry_after].round(4),
         decision[:retry_after].class.name, decision[:tokens_remaining]]
      end

      assert_equal BUCKET, answers
    end

    def test_the_gcra_answers_what_both_backends_answer
      answers = walk do |now|
        decision = @store.check_gcra_limit('parity', 0.05, 0.1, 60)
        [decision[:allowed], decision[:retry_after].round(4),
         decision[:retry_after].class.name]
      end

      assert_equal GCRA, answers
    end

    private

    def walk
      Array.new(BUCKET.length) do |index|
        now = EPOCH + (index * STEP)
        @store.define_singleton_method(:current_time) { now }
        yield(now)
      end
    end
  end
end
