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

    {
      check_gcra_limit: [Storage::Redis::GCRA_SCRIPT, Storage::Redis::GCRA_SHA, ['test', 1, 5, 60]],
      check_token_bucket: [Storage::Redis::TOKEN_BUCKET_SCRIPT, Storage::Redis::TOKEN_BUCKET_SHA, ['test', 5, 1, 60]],
      peek_gcra_limit: [Storage::Redis::PEEK_GCRA_SCRIPT, Storage::Redis::PEEK_GCRA_SHA, ['test', 1, 5]],
      peek_token_bucket: [Storage::Redis::PEEK_TOKEN_BUCKET_SCRIPT, Storage::Redis::PEEK_TOKEN_BUCKET_SHA,
                          ['test', 5, 1]]
    }.each do |operation, (script, sha, arguments)|
      argc = arguments.size

      define_method("test_#{operation}_runs_the_script_by_its_source_sha") do
        redis = FakeRedis.new
        storage = Storage::Redis.new(redis: redis)

        2.times { assert storage.public_send(operation, *arguments)[:allowed] }

        assert_equal Digest::SHA1.hexdigest(script), sha
        assert_equal [[:evalsha, sha, ['throttle:test'], argc]] * 2, redis.calls
      end

      define_method("test_#{operation}_evals_the_source_once_when_the_script_is_missing") do
        redis = FakeRedis.new(cached: false)
        storage = Storage::Redis.new(redis: redis)

        2.times { assert storage.public_send(operation, *arguments)[:allowed] }

        assert_equal [
          [:evalsha, sha, ['throttle:test'], argc],
          [:eval, sha, ['throttle:test'], argc],
          [:evalsha, sha, ['throttle:test'], argc]
        ], redis.calls
      end

      define_method("test_#{operation}_propagates_other_redis_errors") do
        redis = FakeRedis.new(evalsha_error: 'ERR script failed')
        storage = Storage::Redis.new(redis: redis)

        error = assert_raises(::Redis::CommandError) { storage.public_send(operation, *arguments) }

        assert_equal 'ERR script failed', error.message
        assert_equal [[:evalsha, sha, ['throttle:test'], argc]], redis.calls
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
      storage.reset_counter('account:1', 60)

      assert_equal [[:del, ['throttle:account:1']], [:del, ['throttle:account:1']],
                    [:del, ['throttle:account:1:60']]], redis.calls
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

      assert storage.check_gcra_limit('test', 1, 5, 60)[:allowed]
      assert_equal 1, pool.checkouts - checkouts
    end
  end
end
