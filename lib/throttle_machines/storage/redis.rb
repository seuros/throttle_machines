# frozen_string_literal: true

require 'digest/sha1'

module ThrottleMachines
  module Storage
    # Limiter state in Redis, decided atomically by Lua scripts that repeat
    # the native core's arithmetic in Integer nanoseconds.
    #
    # `now` is the server's clock: each script reads Redis TIME (whole
    # microseconds), so processes on any number of hosts share one store and
    # one clock. A server whose clock steps back (NTP, a failover to another
    # host) is the only clock the limits see.
    #
    # Lua numbers are doubles, exact up to 2**53. Stored instants count from
    # a TIME second kept beside them and are rebased to the current second on
    # every write, so they stay small: arithmetic is exact while policy spans
    # are under 2**53 ns (about 104 days) and a key idles no longer than
    # that, which its TTL (twice the limiter's period) bounds.
    class Redis < Base
      NS_PER_MILLISECOND = 1_000_000
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
      INCREMENT_COUNTER_SHA = Digest::SHA1.hexdigest(INCREMENT_COUNTER_SCRIPT)

      # Keys a single SCAN round trip asks for.
      SCAN_BATCH = 100

      def initialize(options = {})
        super
        @redis = options[:redis] || options[:client] || options[:pool]
        @prefix = options[:prefix] || 'throttle:'

        # Validate Redis connection
        validate_redis_connection!
      end

      def increment_counter(key, window, amount = 1)
        run_script(INCREMENT_COUNTER_SCRIPT, INCREMENT_COUNTER_SHA,
                   keys: [window_key(key, window)], argv: [amount, milliseconds(window)])
      end

      def get_counter(key, window)
        with_redis { |r| (r.get(window_key(key, window)) || 0).to_i }
      end

      # Integer nanoseconds until the window's counter expires.
      def get_counter_ttl(key, window)
        ttl = with_redis { |r| r.pttl(window_key(key, window)) }
        [ttl, 0].max * NS_PER_MILLISECOND
      end

      def reset_counter(key, window)
        with_redis { |r| r.del(window_key(key, window)) }
      end

      def check_gcra(key, policy, ttl)
        argv = [policy.emission_interval, policy.delay_tolerance, milliseconds(ttl)]
        allowed, left = run_script(GCRA_SCRIPT, GCRA_SHA, keys: [prefixed(key)], argv: argv)
        allowed == 1 ? Integer(left) : :throttled
      end

      def peek_gcra(key, policy)
        admitted(peek_gcra_reply(key, policy))
      end

      def gcra_retry_after(key, policy)
        Integer(peek_gcra_reply(key, policy)[2])
      end

      def reset_gcra(key)
        delete_state(key)
      end

      def check_token_bucket(key, policy, ttl)
        argv = [policy.capacity, policy.refill_every, milliseconds(ttl)]
        allowed, left = run_script(TOKEN_BUCKET_SCRIPT, TOKEN_BUCKET_SHA, keys: [prefixed(key)], argv: argv)
        allowed == 1 ? Integer(left) : :throttled
      end

      def peek_token_bucket(key, policy)
        admitted(peek_token_bucket_reply(key, policy))
      end

      def token_bucket_retry_after(key, policy)
        Integer(peek_token_bucket_reply(key, policy)[2])
      end

      def reset_token_bucket(key)
        delete_state(key)
      end

      # Utility operations
      def clear(pattern = nil)
        delete_matching(pattern ? prefixed(pattern) : "#{@prefix}#{GLOB_WILDCARD}")
      end

      # The window a counter was written under is unknown here, so the counters
      # go by a glob over the key's own namespace; the key itself is a literal.
      def reset_key(key)
        delete_state(key)
        delete_matching("#{escape_glob(prefixed(key))}#{KEY_SEPARATOR}#{GLOB_WILDCARD}")
      end

      def healthy?
        with_redis { |r| r.ping == 'PONG' }
      rescue StandardError
        false
      end

      private

      def delete_state(key)
        with_redis { |r| r.del(prefixed(key)) }
      end

      # SCAN instead of KEYS, to avoid blocking in production.
      def delete_matching(scan_pattern)
        cursor = '0'

        with_redis do |redis|
          loop do
            cursor, keys = redis.scan(cursor, match: scan_pattern, count: SCAN_BATCH)
            redis.del(*keys) unless keys.empty?
            break if cursor == '0'
          end
        end
      end

      # A peek reply is [allowed, calls admitted, nanoseconds to wait].
      def admitted(reply)
        reply[0] == 1 ? Integer(reply[1]) : :throttled
      end

      def peek_gcra_reply(key, policy)
        argv = [policy.emission_interval, policy.delay_tolerance]
        run_script(PEEK_GCRA_SCRIPT, PEEK_GCRA_SHA, keys: [prefixed(key)], argv: argv)
      end

      def peek_token_bucket_reply(key, policy)
        argv = [policy.capacity, policy.refill_every]
        run_script(PEEK_TOKEN_BUCKET_SCRIPT, PEEK_TOKEN_BUCKET_SHA, keys: [prefixed(key)], argv: argv)
      end

      def window_key(key, window)
        prefixed("#{key}:#{window}")
      end

      # Redis expiries are whole milliseconds; a span rounds up to at least one.
      def milliseconds(nanoseconds)
        [nanoseconds.ceildiv(NS_PER_MILLISECOND), 1].max
      end

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
