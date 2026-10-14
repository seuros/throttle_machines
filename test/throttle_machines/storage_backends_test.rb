# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  # Algorithm behaviour every storage backend must share: the Ruby memory
  # implementation, the native one prepended over it, and the Redis Lua scripts.
  class StorageBackendsTest < Test
    STARTS = [1.0, 12_345.678, 1_700_000_000.0].freeze
    TTL = 60

    # GCRA at rate 10/s, burst 3. After the burst, the TAT is three rounded
    # 0.1 steps ahead and overshoots the 0.2 tolerance by a few ulps, so
    # on-schedule arrivals used to be refused.
    INTERVAL = 0.1
    TOLERANCE = 0.2

    # Token bucket: 3 tokens refilled at 10/s.
    CAPACITY = 3
    REFILL = 10.0

    def setup
      super
      @clock = TestClock.new
    end

    def teardown
      @clock.reset
      super
    end

    def test_memory_ruby
      storage = Storage::Memory.new
      # The native extension prepends its own algorithms; exercise the Ruby ones.
      assert_backend(->(name, *args) { ruby_impl(name).bind_call(storage, *args) })
    end

    def test_memory_native
      skip 'native extension not loaded' unless defined?(Storage::NativeGCRA)

      storage = Storage::Memory.new
      assert_backend(->(name, *args) { storage.public_send(name, *args) })
    end

    # REAL: needs a Redis server; the Lua scripts only run there.
    def test_redis
      skip 'set REDIS_URL to run against a real Redis' unless ENV['REDIS_URL']

      require 'redis'
      prefix = "storage-backends-test-#{Process.pid}:"
      redis = ::Redis.new(url: ENV.fetch('REDIS_URL'))
      storage = Storage::Redis.new(redis: redis, prefix: prefix)
      assert_backend(->(name, *args) { storage.public_send(name, *args) })
    ensure
      redis&.scan_each(match: "#{prefix}*") { |key| redis.del(key) }
    end

    private

    def ruby_impl(name)
      method = Storage::Memory.instance_method(name)
      method.owner == Storage::Memory ? method : method.super_method
    end

    def assert_backend(call)
      STARTS.each do |start|
        assert_gcra_on_schedule(call, start)
        assert_token_bucket_refill(call, start)
      end
    end

    def assert_gcra_on_schedule(call, start)
      key = "gcra-#{start}"
      check = -> { call.(:check_gcra_limit, key, INTERVAL, TOLERANCE, TTL) }
      peek = -> { call.(:peek_gcra_limit, key, INTERVAL, TOLERANCE) }

      @clock.travel_to(start)
      3.times { assert check.()[:allowed], "start #{start}: burst" }

      refused = check.()
      refute refused[:allowed], "start #{start}: fourth instant request"
      assert_in_delta INTERVAL, refused[:retry_after], 1e-6, "start #{start}: retry_after"

      (1..20).each do |k|
        @clock.travel_to(start + (k * INTERVAL))
        assert peek.()[:allowed], "start #{start}: peek at step #{k}"
        assert check.()[:allowed], "start #{start}: on-schedule step #{k}"
      end
    end

    def assert_token_bucket_refill(call, start)
      key = "bucket-#{start}"
      check = -> { call.(:check_token_bucket, key, CAPACITY, REFILL, TTL) }
      peek = -> { call.(:peek_token_bucket, key, CAPACITY, REFILL) }

      @clock.travel_to(start)
      assert_equal [2, 1, 0], Array.new(3) { check.()[:tokens_remaining] }, "start #{start}: drain"

      # Half a token has refilled: the wait is for the other half, not a whole token.
      @clock.travel_to(start + 0.05)
      [peek.(), check.()].each do |refused|
        refute refused[:allowed], "start #{start}: refused at half a token"
        assert_equal 0, refused[:tokens_remaining], "start #{start}: tokens_remaining"
        assert_in_delta 0.05, refused[:retry_after], 1e-6, "start #{start}: retry_after"
      end

      @clock.travel_to(start + 0.1)
      assert check.()[:allowed], "start #{start}: refilled token"
    end
  end
end
