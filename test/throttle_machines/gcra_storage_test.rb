# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  # GCRA behaviour every storage backend must share. Rate 10/s, burst 3:
  # after the burst, the TAT is three rounded 0.1 steps ahead and overshoots
  # the 0.2 tolerance by a few ulps, so on-schedule arrivals used to be refused.
  class GcraStorageTest < Test
    INTERVAL = 0.1
    TOLERANCE = 0.2
    TTL = 60
    STARTS = [1.0, 12_345.678, 1_700_000_000.0].freeze

    def setup
      super
      @clock = TestClock.new
    end

    def teardown
      @clock.reset
      super
    end

    def test_memory_ruby_admits_on_schedule
      storage = Storage::Memory.new
      # The native extension prepends its own GCRA; exercise the Ruby one.
      ruby_check = ruby_gcra(:check_gcra_limit).bind(storage)
      ruby_peek = ruby_gcra(:peek_gcra_limit).bind(storage)

      assert_admits_on_schedule(
        check: ->(key) { ruby_check.call(key, INTERVAL, TOLERANCE, TTL) },
        peek: ->(key) { ruby_peek.call(key, INTERVAL, TOLERANCE) }
      )
    end

    def test_memory_native_admits_on_schedule
      skip 'native extension not loaded' unless defined?(Storage::NativeGCRA)

      assert_admits_on_schedule(**gcra_calls(Storage::Memory.new))
    end

    # REAL: needs a Redis server; the Lua scripts only run there.
    def test_redis_admits_on_schedule
      skip 'set REDIS_URL to run against a real Redis' unless ENV['REDIS_URL']

      require 'redis'
      redis = ::Redis.new(url: ENV.fetch('REDIS_URL'))
      storage = Storage::Redis.new(redis: redis, prefix: "gcra-test-#{Process.pid}:")
      assert_admits_on_schedule(**gcra_calls(storage))
    ensure
      redis&.scan_each(match: "gcra-test-#{Process.pid}:*") { |key| redis.del(key) }
    end

    private

    def gcra_calls(storage)
      {
        check: ->(key) { storage.check_gcra_limit(key, INTERVAL, TOLERANCE, TTL) },
        peek: ->(key) { storage.peek_gcra_limit(key, INTERVAL, TOLERANCE) }
      }
    end

    def ruby_gcra(name)
      method = Storage::Memory.instance_method(name)
      method.owner == Storage::Memory ? method : method.super_method
    end

    def assert_admits_on_schedule(check:, peek:)
      STARTS.each do |start|
        key = "client-#{start}"
        @clock.travel_to(start)
        3.times { assert check.(key)[:allowed], "start #{start}: burst" }

        refused = check.(key)
        refute refused[:allowed], "start #{start}: fourth instant request"
        assert_in_delta INTERVAL, refused[:retry_after], 1e-6, "start #{start}: retry_after"

        (1..20).each do |k|
          @clock.travel_to(start + (k * INTERVAL))
          assert peek.(key)[:allowed], "start #{start}: peek at step #{k}"
          assert check.(key)[:allowed], "start #{start}: on-schedule step #{k}"
        end
      end
    end
  end
end
