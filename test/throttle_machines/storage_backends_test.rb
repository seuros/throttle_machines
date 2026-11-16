# frozen_string_literal: true

require 'test_helper'
require_relative '../support/lua_redis'

module ThrottleMachines
  # Algorithm behaviour every storage backend must share: the memory store
  # over the native gates, and the Redis Lua scripts that repeat their
  # arithmetic (on a real Redis with REDIS_URL, and under LuaJIT through
  # test/support/redis_shim.lua when luajit is on PATH).
  class StorageBackendsTest < Test
    STARTS = [NS, 12_345_678 * MS, 1_700_000_000 * NS].freeze
    TTL = 60 * NS

    # GCRA at 10/s, bursts of 3; a token bucket of 3 refilled at 10/s.
    GCRA = GcraPolicy.per(NS, 10, 3)
    BUCKET = TokenBucketPolicy.new(3, 100 * MS)
    INTERVAL = 100 * MS

    def setup
      super
      @clock = TestClock.new
    end

    def teardown
      @clock.reset
      super
    end

    def test_memory
      storage = Storage::Memory.new(auto_cleanup: false)
      assert_backend(storage)
    ensure
      storage&.shutdown
    end

    # REAL: needs a Redis server. Its TIME cannot be driven, so this checks
    # what holds at any instant within one interval; the LuaJIT tests below
    # walk the clock.
    def test_redis
      skip 'set REDIS_URL to run against a real Redis' unless ENV['REDIS_URL']

      prefix = "storage-backends-test-#{Process.pid}:"
      redis = ::Redis.new(url: ENV.fetch('REDIS_URL'))
      storage = Storage::Redis.new(redis: redis, prefix: prefix)

      assert_equal 3, storage.peek_gcra('gcra', GCRA)
      assert_equal [2, 1, 0, :throttled], Array.new(4) { storage.check_gcra('gcra', GCRA, TTL) }
      assert_includes 1..INTERVAL, storage.gcra_retry_after('gcra', GCRA)
      assert_equal [2, 1, 0, :throttled], Array.new(4) { storage.check_token_bucket('bucket', BUCKET, TTL) }
      assert_equal :throttled, storage.peek_token_bucket('bucket', BUCKET)
      assert_includes 1..INTERVAL, storage.token_bucket_retry_after('bucket', BUCKET)
    ensure
      redis&.scan_each(match: "#{prefix}*") { |key| redis.del(key) }
    end

    # The Redis scripts run under LuaJIT, in a shim of the Redis they run in,
    # its TIME following the test clock: the same answers as the native gates.
    def test_redis_scripts_under_luajit
      skip 'needs luajit on PATH to run the Redis scripts' unless LuaRedis.available?

      redis = LuaRedis.new(time: -> { @clock.now })
      assert_backend(Storage::Redis.new(redis: redis))
    ensure
      redis&.close
    end

    # Reproduces a bug: the scripts took `now` from each process's monotonic
    # clock, so hosts sharing one Redis disagreed on the time, and a host whose
    # clock read further ahead was admitted past a burst another had spent.
    # They read the server's TIME: one clock for every client.
    def test_redis_clients_on_other_hosts_share_the_servers_clock
      skip 'needs luajit on PATH to run the Redis scripts' unless LuaRedis.available?

      server = 1_700_000_000 * NS
      redis = LuaRedis.new(time: -> { server })
      storage = Storage::Redis.new(redis: redis)

      @clock.travel_to(5 * NS) # host A, booted five seconds ago
      assert_equal [2, 1, 0], Array.new(3) { storage.check_gcra('gcra', GCRA, TTL) }
      assert_equal [2, 1, 0], Array.new(3) { storage.check_token_bucket('bucket', BUCKET, TTL) }

      @clock.travel_to(900_000 * NS) # host B, up for ten days
      assert_equal :throttled, storage.check_gcra('gcra', GCRA, TTL)
      assert_equal :throttled, storage.check_token_bucket('bucket', BUCKET, TTL)
      assert_equal [INTERVAL, INTERVAL], [storage.gcra_retry_after('gcra', GCRA),
                                          storage.token_bucket_retry_after('bucket', BUCKET)]

      server += INTERVAL
      @clock.travel_to(NS) # host C, just booted
      assert_equal [0, 0], [storage.check_gcra('gcra', GCRA, TTL), storage.check_token_bucket('bucket', BUCKET, TTL)]
    ensure
      redis&.close
    end

    private

    def assert_backend(storage)
      STARTS.each do |start|
        assert_gcra_on_schedule(storage, start)
        assert_token_bucket_refill(storage, start)
      end
    end

    def assert_gcra_on_schedule(storage, start)
      key = "gcra-#{start}"
      @clock.travel_to(start)

      assert_equal 3, storage.peek_gcra(key, GCRA)
      assert_equal [2, 1, 0], Array.new(3) { storage.check_gcra(key, GCRA, TTL) }, "start #{start}: burst"
      assert_equal :throttled, storage.check_gcra(key, GCRA, TTL), "start #{start}: fourth"
      assert_equal INTERVAL, storage.gcra_retry_after(key, GCRA), "start #{start}: retry_after"

      (1..20).each do |step|
        @clock.travel_to(start + (step * INTERVAL))
        assert_equal 1, storage.peek_gcra(key, GCRA), "start #{start}: peek at step #{step}"
        assert_equal 0, storage.check_gcra(key, GCRA, TTL), "start #{start}: on schedule at step #{step}"
      end
    end

    def assert_token_bucket_refill(storage, start)
      key = "bucket-#{start}"
      @clock.travel_to(start)
      drained = Array.new(3) { storage.check_token_bucket(key, BUCKET, TTL) }

      assert_equal [2, 1, 0], drained, "start #{start}: drain"

      # Half a token has refilled: the wait is for the other half.
      @clock.travel_to(start + (INTERVAL / 2))

      assert_equal :throttled, storage.peek_token_bucket(key, BUCKET)
      assert_equal :throttled, storage.check_token_bucket(key, BUCKET, TTL)
      assert_equal INTERVAL / 2, storage.token_bucket_retry_after(key, BUCKET), "start #{start}: retry_after"

      @clock.travel_to(start + INTERVAL)

      assert_equal 0, storage.check_token_bucket(key, BUCKET, TTL), "start #{start}: refilled token"
    end
  end
end
