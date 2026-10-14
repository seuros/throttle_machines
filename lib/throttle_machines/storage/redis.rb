# frozen_string_literal: true

require 'digest/sha1'

module ThrottleMachines
  module Storage
    class Redis < Base
      # Load Lua scripts from files
      LUA_SCRIPTS_DIR = File.expand_path('redis', __dir__)

      GCRA_SCRIPT = File.read(File.join(LUA_SCRIPTS_DIR, 'gcra.lua'))
      TOKEN_BUCKET_SCRIPT = File.read(File.join(LUA_SCRIPTS_DIR, 'token_bucket.lua'))
      PEEK_GCRA_SCRIPT = File.read(File.join(LUA_SCRIPTS_DIR, 'peek_gcra.lua'))
      PEEK_TOKEN_BUCKET_SCRIPT = File.read(File.join(LUA_SCRIPTS_DIR, 'peek_token_bucket.lua'))
      INCREMENT_COUNTER_SCRIPT = File.read(File.join(LUA_SCRIPTS_DIR, 'increment_counter.lua'))
      # Breaker scripts removed: breaker state is owned by BreakerMachines

      # Redis caches scripts by the SHA1 of their source, so the SHAs are known
      # without a SCRIPT LOAD round trip.
      GCRA_SHA = Digest::SHA1.hexdigest(GCRA_SCRIPT)
      TOKEN_BUCKET_SHA = Digest::SHA1.hexdigest(TOKEN_BUCKET_SCRIPT)
      PEEK_GCRA_SHA = Digest::SHA1.hexdigest(PEEK_GCRA_SCRIPT)
      PEEK_TOKEN_BUCKET_SHA = Digest::SHA1.hexdigest(PEEK_TOKEN_BUCKET_SCRIPT)

      def initialize(options = {})
        super
        @redis = options[:redis] || options[:client] || options[:pool]
        @prefix = options[:prefix] || 'throttle:'

        # Validate Redis connection
        validate_redis_connection!
      end

      # Rate limiting operations
      def increment_counter(key, window, amount = 1)
        window_key = prefixed("#{key}:#{window}")

        # Use Lua script for atomic increment with TTL
        with_redis do |redis|
          redis.eval(INCREMENT_COUNTER_SCRIPT, keys: [window_key], argv: [amount, window.to_i])
        end
      end

      def get_counter(key, window)
        window_key = prefixed("#{key}:#{window}")
        with_redis { |r| (r.get(window_key) || 0).to_i }
      end

      def get_counter_ttl(key, window)
        window_key = prefixed("#{key}:#{window}")
        ttl = with_redis { |r| r.ttl(window_key) }
        [ttl, 0].max
      end

      def reset_counter(key, window)
        window_key = prefixed("#{key}:#{window}")
        with_redis { |r| r.del(window_key) }
      end

      # GCRA operations (atomic via Lua)
      def check_gcra_limit(key, emission_interval, delay_tolerance, ttl)
        now = current_time
        result = run_script(GCRA_SCRIPT, GCRA_SHA,
                            keys: [prefixed(key)],
                            argv: [emission_interval, delay_tolerance, ttl, now])

        allowed = result[0] == 1
        tat = Float(result[1])

        {
          allowed: allowed,
          retry_after: allowed ? 0 : (tat - now - delay_tolerance),
          tat: tat
        }
      end

      # Token bucket operations (atomic via Lua)
      def check_token_bucket(key, capacity, refill_rate, ttl)
        result = run_script(TOKEN_BUCKET_SCRIPT, TOKEN_BUCKET_SHA,
                            keys: [prefixed(key)],
                            argv: [capacity, refill_rate, ttl, current_time])

        allowed = result[0] == 1
        tokens = result[1]

        {
          allowed: allowed,
          retry_after: allowed ? 0 : (1 - tokens) / refill_rate,
          tokens_remaining: tokens.floor
        }
      end

      # Peek methods for non-consuming checks
      def peek_gcra_limit(key, emission_interval, delay_tolerance)
        now = current_time
        result = run_script(PEEK_GCRA_SCRIPT, PEEK_GCRA_SHA,
                            keys: [prefixed(key)],
                            argv: [emission_interval, delay_tolerance, now])

        allowed = result[0] == 1
        tat = Float(result[1])

        {
          allowed: allowed,
          retry_after: allowed ? 0 : (tat - now - delay_tolerance),
          tat: tat
        }
      end

      def peek_token_bucket(key, capacity, refill_rate)
        result = run_script(PEEK_TOKEN_BUCKET_SCRIPT, PEEK_TOKEN_BUCKET_SHA,
                            keys: [prefixed(key)],
                            argv: [capacity, refill_rate, current_time])

        allowed = result[0] == 1
        tokens_remaining = result[1]

        {
          allowed: allowed,
          retry_after: allowed ? 0 : (1 - tokens_remaining) / refill_rate,
          tokens_remaining: tokens_remaining.floor
        }
      end

      # No circuit breaker operations: breaker state is owned by BreakerMachines

      # Utility operations
      def clear(pattern = nil)
        # Use SCAN instead of KEYS to avoid blocking in production
        cursor = '0'
        scan_pattern = pattern ? prefixed(pattern) : "#{@prefix}*"

        with_redis do |redis|
          loop do
            cursor, keys = redis.scan(cursor, match: scan_pattern, count: 100)
            redis.del(*keys) unless keys.empty?
            break if cursor == '0'
          end
        end
      end

      def healthy?
        with_redis { |r| r.ping == 'PONG' }
      rescue StandardError
        false
      end

      private

      def prefixed(key)
        "#{@prefix}#{key}"
      end

      # EVALSHA by the precomputed SHA. A server without the script cached (a
      # restart, SCRIPT FLUSH, failover) answers NOSCRIPT; EVAL then runs the
      # source once and caches it for later calls. Any other error propagates.
      def run_script(script, sha, keys:, argv:)
        with_redis do |redis|
          redis.evalsha(sha, keys: keys, argv: argv)
        rescue ::Redis::CommandError => e
          raise unless e.message.include?('NOSCRIPT')

          redis.eval(script, keys: keys, argv: argv)
        end
      end

      def validate_redis_connection!
        raise ArgumentError, 'Redis client not provided' unless @redis

        # Test connection
        with_redis(&:ping)
      rescue StandardError => e
        raise ArgumentError, "Invalid Redis connection: #{e.message}"
      end

      def with_redis(&block)
        if @redis.respond_to?(:with)
          # Connection pool
          @redis.with(&block)
        else
          # Regular Redis client
          block.call(@redis)
        end
      end
    end
  end
end
