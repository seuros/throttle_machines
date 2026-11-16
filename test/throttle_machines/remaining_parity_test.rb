# frozen_string_literal: true

require 'test_helper'
require 'active_support/cache'
require_relative '../support/lua_redis'

module ThrottleMachines
  # Property: at the instant a check admits a call, the count it answers is
  # what `remaining` reads from storage right after. Limiter#throttle! reports
  # the check's count in its `rate_limit.allowed` event instead of reading
  # storage again, so this parity must hold on every backend and algorithm.
  #
  # Why it holds: GCRA's check moves the arrival time one interval ahead, and
  # peek's `(tolerance + interval - ahead') / interval` with
  # `ahead' = ahead + interval` is check's `(tolerance - ahead) / interval`;
  # a token bucket's check leaves `tokens - 1` with no partial refill to
  # earn; a fixed window's check answers `limit - count`, which peek answers
  # too, and 0 for the call that fills it.
  class RemainingParityTest < Test
    SEED = 20_261_114
    STEPS = 300
    LIMIT = 4
    PERIOD = NS
    ALGORITHMS = %i[gcra token_bucket fixed_window].freeze

    def setup
      super
      @clock = TestClock.new(1_700_000_000 * NS)
      @random = Random.new(SEED)
    end

    def teardown
      @clock.reset
      super
    end

    def test_memory
      storage = Storage::Memory.new(auto_cleanup: false)
      ALGORITHMS.each { |algorithm| assert_parity(storage, algorithm) }
    ensure
      storage&.shutdown
    end

    # Cache keeps fixed windows only, aligned to the wall clock, which moves
    # with the test clock here.
    def test_cache
      storage = Storage::Cache.new(cache_store: ActiveSupport::Cache::MemoryStore.new)
      assert_parity(storage, :fixed_window) { |now| travel_to Time.at(0, now, :nsec) }
    end

    def test_redis_scripts_under_luajit
      skip 'needs luajit on PATH to run the Redis scripts' unless LuaRedis.available?

      redis = LuaRedis.new(time: -> { @clock.now })
      storage = Storage::Redis.new(redis: redis)
      ALGORITHMS.each { |algorithm| assert_parity(storage, algorithm) }
    ensure
      redis&.close
    end

    # REAL: needs a Redis server, whose TIME cannot be driven. An hour-long
    # period keeps every call within one emission interval, so the admitted
    # counts cannot drift between the check and the read.
    def test_redis
      skip 'set REDIS_URL to run against a real Redis' unless ENV['REDIS_URL']

      prefix = "remaining-parity-test-#{Process.pid}:"
      redis = ::Redis.new(url: ENV.fetch('REDIS_URL'))
      storage = Storage::Redis.new(redis: redis, prefix: prefix)
      ALGORITHMS.each do |algorithm|
        limiter = Limiter.new("real-#{algorithm}", limit: LIMIT, period: 3600 * NS, algorithm: algorithm,
                                                   storage: storage)
        admitted = algorithm == :gcra ? 1 : LIMIT # this GCRA has no burst
        answers = Array.new(admitted + 2) { admitted_and_remaining(limiter) }

        assert_equal Array.new(admitted) { [admitted - 1 - it] * 2 } + [[:throttled, 0]] * 2, answers, algorithm
      end
    ensure
      redis&.scan_each(match: "#{prefix}*") { |key| redis.del(key) }
    end

    private

    # Walks the clock in seeded steps (none, part of an interval, up to two
    # periods), so bursts, refusals, partial refills and window rollovers all
    # occur.
    def assert_parity(storage, algorithm)
      limiter = Limiter.new("parity-#{algorithm}", limit: LIMIT, period: PERIOD, algorithm: algorithm,
                                                   storage: storage)
      admitted = 0
      STEPS.times do |step|
        @clock.advance(next_gap)
        yield @clock.now if block_given?
        answer, remaining = admitted_and_remaining(limiter)
        next unless answer.is_a?(Integer)

        admitted += 1
        assert_equal answer, remaining, "#{algorithm} on #{storage.class}, step #{step}"
      end

      assert_operator admitted, :>, STEPS / 10, "#{algorithm} on #{storage.class}: too few admissions"
      assert_operator admitted, :<, STEPS, "#{algorithm} on #{storage.class}: never throttled"
    end

    def admitted_and_remaining(limiter)
      [limiter.send(:check), limiter.remaining]
    end

    def next_gap
      case @random.rand(4)
      when 0 then 0
      when 1 then @random.rand(PERIOD / LIMIT)
      when 2 then @random.rand(PERIOD / 50)
      else @random.rand(PERIOD * 2)
      end
    end
  end
end
