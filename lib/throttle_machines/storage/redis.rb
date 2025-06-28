# frozen_string_literal: true

require_relative 'base'

module ThrottleMachines
  module Storage
    class Redis < Base
      GCRA_SCRIPT = <<~LUA
        local key = KEYS[1]
        local emission_interval = tonumber(ARGV[1])
        local delay_tolerance = tonumber(ARGV[2])
        local ttl = tonumber(ARGV[3])
        local now = tonumber(ARGV[4])

        local tat = redis.call('GET', key)
        if not tat then
          tat = 0
        else
          tat = tonumber(tat)
        end

        tat = math.max(tat, now)
        local allow = (tat - now) <= delay_tolerance

        if allow then
          local new_tat = tat + emission_interval
          redis.call('SET', key, new_tat, 'EX', ttl)
        end

        return { allow and 1 or 0, tat }
      LUA

      TOKEN_BUCKET_SCRIPT = <<~LUA
        local key = KEYS[1]
        local capacity = tonumber(ARGV[1])
        local refill_rate = tonumber(ARGV[2])
        local ttl = tonumber(ARGV[3])
        local now = tonumber(ARGV[4])

        local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
        local tokens = tonumber(bucket[1]) or capacity
        local last_refill = tonumber(bucket[2]) or now

        -- Refill tokens
        local elapsed = now - last_refill
        local tokens_to_add = elapsed * refill_rate
        tokens = math.min(tokens + tokens_to_add, capacity)

        local allow = tokens >= 1
        if allow then
          tokens = tokens - 1
          redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
          redis.call('EXPIRE', key, ttl)
        end

        return { allow and 1 or 0, tokens }
      LUA

      PEEK_GCRA_SCRIPT = <<~LUA
        local key = KEYS[1]
        local emission_interval = tonumber(ARGV[1])
        local delay_tolerance = tonumber(ARGV[2])
        local now = tonumber(ARGV[3])

        local tat = redis.call('GET', key)
        if not tat then
          tat = 0
        else
          tat = tonumber(tat)
        end

        tat = math.max(tat, now)
        local allow = (tat - now) <= delay_tolerance

        return { allow and 1 or 0, tat }
      LUA

      PEEK_TOKEN_BUCKET_SCRIPT = <<~LUA
        local key = KEYS[1]
        local capacity = tonumber(ARGV[1])
        local refill_rate = tonumber(ARGV[2])
        local now = tonumber(ARGV[3])

        local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
        local tokens = tonumber(bucket[1]) or capacity
        local last_refill = tonumber(bucket[2]) or now

        -- Calculate tokens without modifying
        local elapsed = now - last_refill
        local tokens_to_add = elapsed * refill_rate
        tokens = math.min(tokens + tokens_to_add, capacity)

        local allow = tokens >= 1
        local tokens_after = allow and (tokens - 1) or 0

        return { allow and 1 or 0, tokens_after }
      LUA

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
          redis.eval(<<~LUA, keys: [window_key], argv: [amount, window.to_i])
            local count = redis.call('INCRBY', KEYS[1], ARGV[1])
            local ttl = redis.call('TTL', KEYS[1])

            -- Set expiry if key is new (ttl == -2) or has no TTL (ttl == -1)
            if ttl <= 0 then
              redis.call('EXPIRE', KEYS[1], ARGV[2])
            end

            return count
          LUA
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
          redis.eval(<<~LUA, keys: [breaker_key], argv: [current_time])
            local data = redis.call('HGETALL', KEYS[1])
            if #data == 0 then
              return {}
            end

            local state = {}
            for i = 1, #data, 2 do
              state[data[i]] = data[i + 1]
            end

            -- Auto-transition from open to half-open if timeout passed
            if state['state'] == 'open' and state['opens_at'] then
              local now = tonumber(ARGV[1])
              local opens_at = tonumber(state['opens_at'])
            #{'  '}
              if now >= opens_at then
                redis.call('HSET', KEYS[1], 'state', 'half_open', 'half_open_attempts', '0')
                state['state'] = 'half_open'
                state['half_open_attempts'] = '0'
              end
            end

            return state
          LUA
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
          redis.eval(<<~LUA, keys: [breaker_key], argv: [half_open_requests])
            local state = redis.call('HGET', KEYS[1], 'state')

            if state == 'half_open' then
              -- Increment half-open attempts and potentially close the circuit
              local attempts = redis.call('HINCRBY', KEYS[1], 'half_open_attempts', 1)
            #{'  '}
              if attempts >= tonumber(ARGV[1]) then
                redis.call('DEL', KEYS[1])
              end
            elseif state == 'closed' then
              -- Reset failure count on success in closed state
              local failures = redis.call('HGET', KEYS[1], 'failures')
              if failures and tonumber(failures) > 0 then
                redis.call('HSET', KEYS[1], 'failures', 0)
              end
            end
          LUA
        end
      end

      def record_breaker_failure(key, threshold, timeout)
        breaker_key = prefixed("breaker:#{key}")
        now = current_time

        # Use Lua script for atomic failure recording
        with_redis do |redis|
          redis.eval(<<~LUA, keys: [breaker_key], argv: [threshold, timeout, now])
            local state = redis.call('HGET', KEYS[1], 'state') or 'closed'
            local now = ARGV[3]
            local timeout = tonumber(ARGV[2])

            if state == 'half_open' then
              -- Failure in half-open state, just re-open the circuit
              redis.call('HMSET', KEYS[1],
                'state', 'open',
                'opens_at', tonumber(now) + timeout,
                'last_failure', now
              )
            else -- state is 'closed' or nil
              local failures = redis.call('HINCRBY', KEYS[1], 'failures', 1)
              redis.call('HSET', KEYS[1], 'last_failure', now)
            #{'  '}
              if failures >= tonumber(ARGV[1]) then
                redis.call('HMSET', KEYS[1],
                  'state', 'open',
                  'opens_at', tonumber(now) + timeout
                )
              end
            end

            redis.call('EXPIRE', KEYS[1], timeout * 2)
          LUA
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
