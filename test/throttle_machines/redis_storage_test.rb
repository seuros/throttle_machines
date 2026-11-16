# frozen_string_literal: true

require 'test_helper'
require 'redis'
require 'digest/sha1'

module ThrottleMachines
  class RedisStorageTest < Test
    NOSCRIPT = 'NOSCRIPT No matching script. Please use EVAL.'

    # Records each script call. EVALSHA answers NOSCRIPT until the script is
    # cached, which EVAL does, as Redis would.
    class FakeRedis
      attr_reader :calls

      def initialize(cached: true, evalsha_error: nil, eval_error: nil)
        @cached = cached
        @evalsha_error = evalsha_error
        @eval_error = eval_error
        @calls = []
      end

      def ping
        'PONG'
      end

      def evalsha(sha, keys:, argv:)
        @calls << [:evalsha, sha, keys, argv.size]
        raise ::Redis::CommandError, @evalsha_error if @evalsha_error
        raise ::Redis::CommandError, NOSCRIPT unless @cached

        [1, 5]
      end

      def eval(script, keys:, argv:)
        @calls << [:eval, Digest::SHA1.hexdigest(script), keys, argv.size]
        raise ::Redis::CommandError, @eval_error if @eval_error

        @cached = true
        [1, 5]
      end

      def del(*keys)
        @calls << [:del, keys]
        keys.size
      end

      def scan(_cursor, match:, count:)
        @calls << [:scan, match, count]
        ['0', []]
      end
    end

    # Hands out one connection, like ConnectionPool#with.
    class FakePool
      attr_reader :checkouts

      def initialize(redis)
        @redis = redis
        @checkouts = 0
      end

      def with
        @checkouts += 1
        yield @redis
      end
    end

    GCRA = GcraPolicy.new(NS, 5 * NS)
    BUCKET = TokenBucketPolicy.new(5, NS)
    TTL = 60 * NS

    COUNTER_KEY = "throttle:test:#{TTL}".freeze

    # operation => script, its SHA, arguments, the key it writes, argv size,
    # and its answer to FakeRedis's [1, 5] reply.
    {
      check_gcra: [Storage::Redis::GCRA_SCRIPT, Storage::Redis::GCRA_SHA, ['test', GCRA, TTL],
                   'throttle:test', 3, 5],
      check_token_bucket: [Storage::Redis::TOKEN_BUCKET_SCRIPT, Storage::Redis::TOKEN_BUCKET_SHA,
                           ['test', BUCKET, TTL], 'throttle:test', 3, 5],
      peek_gcra: [Storage::Redis::PEEK_GCRA_SCRIPT, Storage::Redis::PEEK_GCRA_SHA, ['test', GCRA],
                  'throttle:test', 2, 5],
      peek_token_bucket: [Storage::Redis::PEEK_TOKEN_BUCKET_SCRIPT, Storage::Redis::PEEK_TOKEN_BUCKET_SHA,
                          ['test', BUCKET], 'throttle:test', 2, 5],
      increment_counter: [Storage::Redis::INCREMENT_COUNTER_SCRIPT, Storage::Redis::INCREMENT_COUNTER_SHA,
                          ['test', TTL], COUNTER_KEY, 2, [1, 5]]
    }.each do |operation, (script, sha, arguments, key, argc, answer)|
      define_method("test_#{operation}_runs_the_script_by_its_source_sha") do
        redis = FakeRedis.new
        storage = Storage::Redis.new(redis: redis)

        2.times { assert_equal answer, storage.public_send(operation, *arguments) }

        assert_equal Digest::SHA1.hexdigest(script), sha
        assert_equal [[:evalsha, sha, [key], argc]] * 2, redis.calls
      end

      define_method("test_#{operation}_evals_the_source_once_when_the_script_is_missing") do
        redis = FakeRedis.new(cached: false)
        storage = Storage::Redis.new(redis: redis)

        2.times { assert_equal answer, storage.public_send(operation, *arguments) }

        assert_equal [
          [:evalsha, sha, [key], argc],
          [:eval, sha, [key], argc],
          [:evalsha, sha, [key], argc]
        ], redis.calls
      end

      define_method("test_#{operation}_propagates_other_redis_errors") do
        redis = FakeRedis.new(evalsha_error: 'ERR script failed')
        storage = Storage::Redis.new(redis: redis)

        error = assert_raises(::Redis::CommandError) { storage.public_send(operation, *arguments) }

        assert_equal 'ERR script failed', error.message
        assert_equal [[:evalsha, sha, [key], argc]], redis.calls
      end

      define_method("test_#{operation}_does_not_retry_a_failed_eval") do
        redis = FakeRedis.new(cached: false, eval_error: NOSCRIPT)
        storage = Storage::Redis.new(redis: redis)

        error = assert_raises(::Redis::CommandError) { storage.public_send(operation, *arguments) }

        assert_equal NOSCRIPT, error.message
        assert_equal %i[evalsha eval], redis.calls.map(&:first)
      end
    end

    def test_a_reset_deletes_the_one_key_its_algorithm_wrote
      redis = FakeRedis.new
      storage = Storage::Redis.new(redis: redis)

      storage.reset_gcra('account:1')
      storage.reset_token_bucket('account:1')
      storage.reset_counter('account:1', 60 * NS)

      assert_equal [[:del, ['throttle:account:1']], [:del, ['throttle:account:1']],
                    [:del, ["throttle:account:1:#{60 * NS}"]]], redis.calls
    end

    def test_reset_key_scans_the_keys_own_namespace_with_the_key_as_a_literal
      redis = FakeRedis.new
      storage = Storage::Redis.new(redis: redis)

      storage.reset_key('ip:[::1]*')

      assert_equal [[:del, ['throttle:ip:[::1]*']],
                    [:scan, 'throttle:ip:\[::1\]\*:*', Storage::Redis::SCAN_BATCH]], redis.calls
    end

    def test_falls_back_on_the_same_pooled_connection
      pool = FakePool.new(FakeRedis.new(cached: false))
      storage = Storage::Redis.new(pool: pool)
      checkouts = pool.checkouts

      assert_equal 5, storage.check_gcra('test', GCRA, TTL)
      assert_equal 1, pool.checkouts - checkouts
    end

    # Answers each script call with the next canned reply, recording argv.
    class ScriptedRedis < FakeRedis
      attr_reader :argvs

      def initialize(*replies)
        super()
        @replies = replies
        @argvs = []
      end

      def evalsha(_sha, keys:, argv:)
        @argvs << argv
        @replies.shift
      end
    end

    def test_a_throttled_reply_answers_the_refusal_symbol
      storage = Storage::Redis.new(redis: ScriptedRedis.new([0, 0], [0, 0]))

      assert_equal :throttled, storage.check_gcra('test', GCRA, TTL)
      assert_equal :throttled, storage.check_token_bucket('test', BUCKET, TTL)
    end

    def test_a_peek_reply_carries_the_wait_in_nanoseconds
      storage = Storage::Redis.new(redis: ScriptedRedis.new([0, 0, '1500000000'], [0, 0, '7']))

      assert_equal 1_500_000_000, storage.gcra_retry_after('test', GCRA)
      assert_equal 7, storage.token_bucket_retry_after('test', BUCKET)
    end

    # No clock is passed: the scripts read the server's TIME, so this
    # process's monotonic clock never reaches them.
    def test_scripts_take_policy_spans_in_nanoseconds_and_the_ttl_in_whole_milliseconds
      clock = TestClock.new(42)
      redis = ScriptedRedis.new([1, 4], [1, 4], [1, 4, 0], [1, 4, 0])
      storage = Storage::Redis.new(redis: redis)

      storage.check_gcra('test', GCRA, TTL + 1)
      storage.check_token_bucket('test', BUCKET, 1)
      storage.peek_gcra('test', GCRA)
      storage.peek_token_bucket('test', BUCKET)

      assert_equal [[NS, 5 * NS, 60_001], [5, NS, 1], [NS, 5 * NS], [5, NS]], redis.argvs
    ensure
      clock&.reset
    end
  end
end
