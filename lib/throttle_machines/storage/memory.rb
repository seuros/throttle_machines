# frozen_string_literal: true

require 'concurrent'

module ThrottleMachines
  module Storage
    class Memory < Base
      DEFAULT_MAX_KEYS = 65_536
      CAPACITY_RETRY_AFTER = 1.0

      def initialize(options = {})
        super
        @max_keys = options.fetch(:max_keys, DEFAULT_MAX_KEYS)
        unless @max_keys.is_a?(Integer) && @max_keys >= 0
          raise ArgumentError, 'max_keys must be a non-negative integer'
        end

        @stored_keys = 0
        @capacity_lock = Mutex.new
        @capacity_cleanup_lock = Mutex.new
        @next_capacity_cleanup_at = -Float::INFINITY
        @counters = Concurrent::Hash.new
        @gcra_states = Concurrent::Hash.new
        @token_buckets = Concurrent::Hash.new

        # Use a striped lock pattern - pool of locks for fine-grained concurrency
        @lock_pool_size = options[:lock_pool_size] || 32
        @locks = Array.new(@lock_pool_size) { Concurrent::ReadWriteLock.new }

        # Background cleanup thread
        @cleanup_interval = options[:cleanup_interval] || 60
        @shutdown = false
        @cleanup_thread = start_cleanup_thread if options[:auto_cleanup] != false

        # Ensure cleanup on garbage collection
        ObjectSpace.define_finalizer(self, self.class.finalizer(@cleanup_thread))
      end

      def self.finalizer(cleanup_thread)
        proc { cleanup_thread&.kill }
      end

      # Rate limiting operations
      def increment_counter(key, window, amount = 1)
        window_key = "#{key}:#{window}"
        reclaim_capacity

        with_write_lock(window_key) do
          now = current_time
          # Fetch fresh value inside the lock to ensure consistency
          counter = @counters[window_key]

          if counter.nil? || counter[:expires_at] <= now
            # Create or reset counter atomically
            new_count = amount
            stored = store_entry(@counters, window_key, { count: new_count, expires_at: now + window })
          else
            # Increment existing counter atomically
            new_count = counter[:count] + amount
            stored = store_entry(@counters, window_key, { count: new_count, expires_at: counter[:expires_at] })
          end
          # An untrackable counter must never look like an admitted request.
          stored ? new_count : Float::INFINITY
        end
      end

      def get_counter(key, window)
        window_key = "#{key}:#{window}"
        reclaim_capacity

        with_read_lock(window_key) do
          counter = @counters[window_key]
          return capacity_available?(@counters, window_key) ? 0 : Float::INFINITY unless counter
          return 0 if counter[:expires_at] <= current_time

          counter[:count]
        end
      end

      def get_counter_ttl(key, window)
        window_key = "#{key}:#{window}"

        with_read_lock(window_key) do
          counter = @counters[window_key]
          return capacity_available?(@counters, window_key) ? 0 : CAPACITY_RETRY_AFTER unless counter

          ttl = counter[:expires_at] - current_time
          [ttl, 0].max
        end
      end

      def reset_counter(key, window)
        window_key = "#{key}:#{window}"
        with_write_lock(window_key) { delete_entry(@counters, window_key) }
      end

      # GCRA operations (atomic simulation)
      def check_gcra_limit(key, emission_interval, delay_tolerance, ttl)
        reclaim_capacity
        with_write_lock(key) do
          now = current_time
          state = @gcra_states[key] || { tat: 0.0 }

          tat = [state[:tat], now].max
          allow = gcra_allowed?(tat, now, delay_tolerance)

          if allow
            new_tat = tat + emission_interval
            unless store_entry(@gcra_states, key, { tat: new_tat, expires_at: now + ttl })
              return capacity_gcra_refusal(now, delay_tolerance)
            end
          end

          {
            allowed: allow,
            retry_after: allow ? 0 : (tat - now - delay_tolerance),
            tat: tat
          }
        end
      end

      def peek_gcra_limit(key, _emission_interval, delay_tolerance)
        reclaim_capacity
        with_read_lock(key) do
          now = current_time
          return capacity_gcra_refusal(now, delay_tolerance) unless capacity_available?(@gcra_states, key)

          state = @gcra_states[key] || { tat: 0.0 }

          tat = [state[:tat], now].max
          allow = gcra_allowed?(tat, now, delay_tolerance)

          {
            allowed: allow,
            retry_after: allow ? 0 : (tat - now - delay_tolerance),
            tat: tat
          }
        end
      end

      # Token bucket operations (atomic simulation)
      def check_token_bucket(key, capacity, refill_rate, ttl)
        reclaim_capacity
        with_write_lock(key) do
          now = current_time
          bucket = @token_buckets[key] || { tokens: capacity, last_refill: now }

          # Refill tokens
          elapsed = now - bucket[:last_refill]
          tokens_to_add = elapsed * refill_rate
          bucket[:tokens] = [bucket[:tokens] + tokens_to_add, capacity].min
          bucket[:last_refill] = now

          # Check if we can consume a token
          if token_available?(bucket[:tokens], now, refill_rate)
            bucket[:tokens] = [bucket[:tokens] - 1, 0.0].max
            unless store_entry(@token_buckets, key, bucket.merge(expires_at: now + ttl))
              return capacity_token_bucket_refusal
            end

            {
              allowed: true,
              retry_after: 0,
              tokens_remaining: bucket[:tokens].floor
            }
          else
            retry_after = (1 - bucket[:tokens]) / refill_rate

            {
              allowed: false,
              retry_after: retry_after,
              tokens_remaining: 0
            }
          end
        end
      end

      def peek_token_bucket(key, capacity, refill_rate)
        reclaim_capacity
        with_read_lock(key) do
          now = current_time
          return capacity_token_bucket_refusal unless capacity_available?(@token_buckets, key)

          bucket = @token_buckets[key] || { tokens: capacity, last_refill: now }

          # Calculate tokens without modifying state
          elapsed = now - bucket[:last_refill]
          tokens_to_add = elapsed * refill_rate
          current_tokens = [bucket[:tokens] + tokens_to_add, capacity].min

          if token_available?(current_tokens, now, refill_rate)
            {
              allowed: true,
              retry_after: 0,
              tokens_remaining: [current_tokens - 1, 0].max.floor
            }
          else
            retry_after = (1 - current_tokens) / refill_rate

            {
              allowed: false,
              retry_after: retry_after,
              tokens_remaining: 0
            }
          end
        end
      end

      # No circuit breaker operations here: breaker state is owned by BreakerMachines

      # Utility operations
      def clear(pattern = nil)
        if pattern
          regex = Regexp.new(pattern.gsub('*', '.*'))

          # Clear matching keys from all stores
          [@counters, @gcra_states, @token_buckets].each do |store|
            store.keys.each do |k|
              with_write_lock(k) { delete_entry(store, k) } if k&.match?(regex)
            end
          end
        else
          @capacity_lock.synchronize do
            @counters.clear
            @gcra_states.clear
            @token_buckets.clear
            @stored_keys = 0
          end
        end
      end

      def healthy?
        true
      end

      def shutdown
        @shutdown = true
        @cleanup_thread&.join(1) # Wait up to 1 second for graceful shutdown
        @cleanup_thread&.kill if @cleanup_thread&.alive?
        @cleanup_thread = nil
      end

      private

      # Called with the key's write lock held. The short admission lock makes
      # the cap atomic across stripes and all three stores.
      def store_entry(store, key, value)
        @capacity_lock.synchronize do
          new_key = !store.key?(key)
          return false if new_key && @stored_keys >= @max_keys

          store[key] = value
          @stored_keys += 1 if new_key
          true
        end
      end

      def delete_entry(store, key)
        @capacity_lock.synchronize do
          value = store.delete(key)
          @stored_keys -= 1 if value
          value
        end
      end

      def capacity_available?(store, key)
        @capacity_lock.synchronize { store.key?(key) || @stored_keys < @max_keys }
      end

      def capacity_gcra_refusal(now, delay_tolerance)
        { allowed: false, retry_after: CAPACITY_RETRY_AFTER, tat: now + delay_tolerance + CAPACITY_RETRY_AFTER }
      end

      def capacity_token_bucket_refusal
        { allowed: false, retry_after: CAPACITY_RETRY_AFTER, tokens_remaining: 0 }
      end

      # Run before taking any striped lock. At saturation, attempt expiry
      # cleanup at most once per second, even with auto_cleanup disabled.
      # Rejected identity sprays must not trigger a full scan on every call.
      def reclaim_capacity
        return unless @capacity_lock.synchronize { @stored_keys >= @max_keys }
        return unless @capacity_cleanup_lock.try_lock

        begin
          now = current_time
          return if now < @next_capacity_cleanup_at

          @next_capacity_cleanup_at = now + CAPACITY_RETRY_AFTER
          clean_expired_entries
        ensure
          @capacity_cleanup_lock.unlock
        end
      end

      def with_read_lock(key, &block)
        lock_for(key).with_read_lock(&block)
      end

      def with_write_lock(key, &block)
        lock_for(key).with_write_lock(&block)
      end

      def lock_for(key)
        # Hash key to determine which lock to use
        index = key.hash.abs % @lock_pool_size
        @locks[index]
      end

      def start_cleanup_thread
        Thread.new do
          loop do
            break if @shutdown

            sleep @cleanup_interval
            break if @shutdown

            clean_expired_entries
          end
        end
      end

      def clean_expired_entries
        now = current_time

        [@counters, @gcra_states, @token_buckets].each do |store|
          store.keys.each do |key|
            with_write_lock(key) do
              # Re-read under the lock: a writer may have refreshed the TTL.
              data = store[key]
              delete_entry(store, key) if data && data[:expires_at] && data[:expires_at] <= now
            end
          end
        end

        # No breaker state cleanup: breaker state is managed by BreakerMachines
      rescue StandardError => e
        # Log error but don't crash cleanup thread
        warn "ThrottleMachines: Cleanup error: #{e.message}"
      end
    end
  end
end
