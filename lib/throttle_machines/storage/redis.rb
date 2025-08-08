# frozen_string_literal: true

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
      GET_BREAKER_STATE_SCRIPT = File.read(File.join(LUA_SCRIPTS_DIR, 'get_breaker_state.lua'))
      RECORD_BREAKER_SUCCESS_SCRIPT = File.read(File.join(LUA_SCRIPTS_DIR, 'record_breaker_success.lua'))
      RECORD_BREAKER_FAILURE_SCRIPT = File.read(File.join(LUA_SCRIPTS_DIR, 'record_breaker_failure.lua'))

      def initialize(options = {})
        super
        @redis = options[:redis] || options[:client] || options[:pool]
        @prefix = options[:prefix] || 'throttle:'

        # Cache scripts to avoid repeated script loads
        @gcra_sha = nil
        @token_bucket_sha = nil
        @peek_gcra_sha = nil
        @peek_token_bucket_sha = nil

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
        ensure_gcra_script_loaded!

        result = with_redis do |redis|
          redis.evalsha(
            @gcra_sha,
            keys: [prefixed(key)],
            argv: [emission_interval, delay_tolerance, ttl, current_time]
          )
        end

        allowed = result[0] == 1
        tat = result[1]
        now = current_time

        {
          allowed: allowed,
          retry_after: allowed ? 0 : (tat - now - delay_tolerance),
          tat: tat
        }
      rescue ::Redis::CommandError => e
        raise unless e.message.include?('NOSCRIPT')

        @gcra_sha = nil
        retry
      end

      # Token bucket operations (atomic via Lua)
      def check_token_bucket(key, capacity, refill_rate, ttl)
        ensure_token_bucket_script_loaded!

        result = with_redis do |redis|
          redis.evalsha(
            @token_bucket_sha,
            keys: [prefixed(key)],
            argv: [capacity, refill_rate, ttl, current_time]
          )
        end

        allowed = result[0] == 1
        tokens = result[1]

        {
          allowed: allowed,
          retry_after: allowed ? 0 : (1 - tokens) / refill_rate,
          tokens_remaining: tokens.floor
        }
      rescue ::Redis::CommandError => e
        raise unless e.message.include?('NOSCRIPT')

        @token_bucket_sha = nil
        retry
      end

      # Peek methods for non-consuming checks
      def peek_gcra_limit(key, emission_interval, delay_tolerance)
        ensure_peek_gcra_script_loaded!

        result = with_redis do |redis|
          redis.evalsha(
            @peek_gcra_sha,
            keys: [prefixed(key)],
            argv: [emission_interval, delay_tolerance, current_time]
          )
        end

        allowed = result[0] == 1
        tat = result[1]
        now = current_time

        {
          allowed: allowed,
          retry_after: allowed ? 0 : (tat - now - delay_tolerance),
          tat: tat
        }
      rescue ::Redis::CommandError => e
        raise unless e.message.include?('NOSCRIPT')

        @peek_gcra_sha = nil
        retry
      end

      def peek_token_bucket(key, capacity, refill_rate)
        ensure_peek_token_bucket_script_loaded!

        result = with_redis do |redis|
          redis.evalsha(
            @peek_token_bucket_sha,
            keys: [prefixed(key)],
            argv: [capacity, refill_rate, current_time]
          )
        end

        allowed = result[0] == 1
        tokens_remaining = result[1]

        {
          allowed: allowed,
          retry_after: allowed ? 0 : (1 - tokens_remaining) / refill_rate,
          tokens_remaining: tokens_remaining.floor
        }
      rescue ::Redis::CommandError => e
        raise unless e.message.include?('NOSCRIPT')

        @peek_token_bucket_sha = nil
        retry
      end

      # Circuit breaker operations
      def get_breaker_state(key)
        breaker_key = prefixed("breaker:#{key}")

        # Use Lua script for atomic read and potential state transition
        result = with_redis do |redis|
          redis.eval(GET_BREAKER_STATE_SCRIPT, keys: [breaker_key], argv: [current_time])
        end

        return { state: :closed, failures: 0, last_failure: nil } if result.empty?

        # Convert hash from Lua to Ruby format
        state = {}
        result.each_slice(2) { |k, v| state[k] = v }

        {
          state: state['state'].to_sym,
          failures: state['failures'].to_i,
          last_failure: state['last_failure']&.to_f,
          opens_at: state['opens_at']&.to_f,
          half_open_attempts: state['half_open_attempts']&.to_i
        }
      end

      def record_breaker_success(key, _timeout, half_open_requests = 1)
        breaker_key = prefixed("breaker:#{key}")

        # Use Lua script for atomic success recording
        with_redis do |redis|
          redis.eval(RECORD_BREAKER_SUCCESS_SCRIPT, keys: [breaker_key], argv: [half_open_requests])
        end
      end

      def record_breaker_failure(key, threshold, timeout)
        breaker_key = prefixed("breaker:#{key}")
        now = current_time

        # Use Lua script for atomic failure recording
        with_redis do |redis|
          redis.eval(RECORD_BREAKER_FAILURE_SCRIPT, keys: [breaker_key], argv: [threshold, timeout, now])
        end

        get_breaker_state(key)
      end

      def trip_breaker(key, timeout)
        breaker_key = prefixed("breaker:#{key}")
        now = current_time

        with_redis do |redis|
          redis.hmset(breaker_key,
                      'state', 'open',
                      'failures', 0,
                      'last_failure', now,
                      'opens_at', now + timeout)
          redis.expire(breaker_key, (timeout * 2).to_i)
        end
      end

      def reset_breaker(key)
        with_redis { |r| r.del(prefixed("breaker:#{key}")) }
      end

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

      def ensure_gcra_script_loaded!
        @ensure_gcra_script_loaded ||= with_redis { |r| r.script(:load, GCRA_SCRIPT) }
      end

      def ensure_token_bucket_script_loaded!
        @ensure_token_bucket_script_loaded ||= with_redis { |r| r.script(:load, TOKEN_BUCKET_SCRIPT) }
      end

      def ensure_peek_gcra_script_loaded!
        @ensure_peek_gcra_script_loaded ||= with_redis { |r| r.script(:load, PEEK_GCRA_SCRIPT) }
      end

      def ensure_peek_token_bucket_script_loaded!
        @ensure_peek_token_bucket_script_loaded ||= with_redis { |r| r.script(:load, PEEK_TOKEN_BUCKET_SCRIPT) }
      end

      def validate_redis_connection!
        raise ArgumentError, 'Redis client not provided' unless @redis

        # Test connection
        with_redis(&:ping)
      rescue StandardError => e
        raise ArgumentError, "Invalid Redis connection: #{e.message}"
      end

      def with_redis(&)
        if @redis.respond_to?(:with)
          # Connection pool
          @redis.with(&)
        else
          # Regular Redis client
          yield @redis
        end
      end
    end
  end
end
