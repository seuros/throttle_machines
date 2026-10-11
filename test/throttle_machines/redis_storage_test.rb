# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'redis'
require 'digest/sha1'

module ThrottleMachines
  class RedisStorageTest < Test
    {
      check_gcra_limit: [Storage::Redis::GCRA_SCRIPT, ['test', 1, 5, 60]],
      check_token_bucket: [Storage::Redis::TOKEN_BUCKET_SCRIPT, ['test', 5, 1, 60]],
      peek_gcra_limit: [Storage::Redis::PEEK_GCRA_SCRIPT, ['test', 1, 5]],
      peek_token_bucket: [Storage::Redis::PEEK_TOKEN_BUCKET_SCRIPT, ['test', 5, 1]]
    }.each do |operation, (script, arguments)|
      define_method("test_#{operation}_loads_and_reuses_script_sha") do
        redis = Minitest::Mock.new
        redis.expect(:ping, 'PONG')
        sha = Digest::SHA1.hexdigest(script)
        redis.expect(:script, sha, [:load, script])
        2.times { expect_evalsha(redis, sha) }

        storage = Storage::Redis.new(redis: redis)
        2.times { assert storage.public_send(operation, *arguments)[:allowed] }

        redis.verify
      end

      define_method("test_#{operation}_reloads_missing_script") do
        redis = Minitest::Mock.new
        redis.expect(:ping, 'PONG')
        sha = Digest::SHA1.hexdigest(script)
        redis.expect(:script, sha, [:load, script])
        expect_evalsha(redis, sha)
        redis.expect(:evalsha, nil) do |actual_sha, **_options|
          assert_equal sha, actual_sha
          raise ::Redis::CommandError, 'NOSCRIPT No matching script. Please use EVAL.'
        end
        redis.expect(:script, sha, [:load, script])
        expect_evalsha(redis, sha)

        storage = Storage::Redis.new(redis: redis)
        2.times { assert storage.public_send(operation, *arguments)[:allowed] }

        redis.verify
      end

      define_method("test_#{operation}_propagates_other_redis_errors") do
        redis = Minitest::Mock.new
        redis.expect(:ping, 'PONG')
        sha = Digest::SHA1.hexdigest(script)
        redis.expect(:script, sha, [:load, script])
        redis.expect(:evalsha, nil) do |actual_sha, **_options|
          assert_equal sha, actual_sha
          raise ::Redis::CommandError, 'ERR script failed'
        end

        storage = Storage::Redis.new(redis: redis)
        error = assert_raises(::Redis::CommandError) { storage.public_send(operation, *arguments) }

        assert_equal 'ERR script failed', error.message
        redis.verify
      end
    end

    private

    def expect_evalsha(redis, sha)
      redis.expect(:evalsha, [1, 5]) do |actual_sha, keys:, argv:|
        assert_equal sha, actual_sha
        assert_equal ['throttle:test'], keys
        assert_predicate argv, :any?
        true
      end
    end
  end
end
