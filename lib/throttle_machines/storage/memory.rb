# frozen_string_literal: true

require 'concurrent'

module ThrottleMachines
  module Storage
    class Memory < Base
      DEFAULT_MAX_KEYS = 65_536
      # Integer nanoseconds a key refused as :full is told to wait.
      CAPACITY_RETRY_AFTER = NS_PER_SECOND
      # Integer nanoseconds between background sweeps of expired entries.
      DEFAULT_CLEANUP_INTERVAL = 60 * NS_PER_SECOND
      DEFAULT_LOCK_POOL_SIZE = 32
      SHUTDOWN_GRACE = 1.0

      def initialize(options = {})
        super
        max_keys = options.fetch(:max_keys, DEFAULT_MAX_KEYS)
        raise TypeError, "max_keys must be an Integer, got #{max_keys.inspect}" unless max_keys.is_a?(Integer)
        raise RangeError, "max_keys must not be negative, got #{max_keys}" if max_keys.negative?

        @state = State.new(
          max_keys: max_keys,
          lock_pool_size: options[:lock_pool_size] || DEFAULT_LOCK_POOL_SIZE,
          cleanup_interval: options[:cleanup_interval] || DEFAULT_CLEANUP_INTERVAL
        )
        @counters = @state.counters
        @gcra_states = @state.gcra_states
        @token_buckets = @state.token_buckets

        @capacity_cleanup_lock = Mutex.new
        @next_capacity_cleanup_at = nil
        @cleanup_thread = nil

        return if options[:auto_cleanup] == false

        @cleanup_thread = @state.start_cleanup_thread
        ObjectSpace.define_finalizer(self, self.class.finalizer(@cleanup_thread))
      end

      def self.finalizer(cleanup_thread)
        proc { cleanup_thread.kill }
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
          stored ? new_count : UNTRACKED
        end
      end

      def get_counter(key, window)
        window_key = "#{key}:#{window}"
        reclaim_capacity

        with_read_lock(window_key) do
          counter = @counters[window_key]
          return capacity_available?(@counters, window_key) ? 0 : UNTRACKED unless counter
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

      # GCRA and token bucket state is the core gate's own, kept per key as
      # the values `restored` takes, so a limiter whose policy changes
      # resumes from where the key's state left off. A refusal stores
      # nothing.
      def check_gcra(key, policy, ttl)
        reclaim_capacity
        with_write_lock(key) do
          now = current_time
          entry = @gcra_states[key]
          return :full unless entry || capacity_available?(@gcra_states, key)

          gate = entry ? Gcra.restored(policy, entry[:tat]) : Gcra.new(policy)
          answer = gate.check(now)
          return answer unless answer.is_a?(Integer)
          return :full unless store_entry(@gcra_states, key, { tat: gate.tat, expires_at: now + ttl })

          answer
        end
      end

      def peek_gcra(key, policy)
        reclaim_capacity
        with_read_lock(key) do
          gate = gcra_gate(key, policy)
          gate ? gate.peek(current_time) : :full
        end
      end

      def gcra_retry_after(key, policy)
        with_read_lock(key) do
          gate = gcra_gate(key, policy)
          gate ? gate.retry_after(current_time) : CAPACITY_RETRY_AFTER
        end
      end

      def reset_gcra(key)
        with_write_lock(key) { delete_entry(@gcra_states, key) }
      end

      def check_token_bucket(key, policy, ttl)
        reclaim_capacity
        with_write_lock(key) do
          now = current_time
          entry = @token_buckets[key]
          return :full unless entry || capacity_available?(@token_buckets, key)

          gate = entry ? restored_bucket(policy, entry) : TokenBucket.new(policy)
          answer = gate.check(now)
          return answer unless answer.is_a?(Integer)

          state = { tokens: gate.tokens, refilled_at: gate.refilled_at, expires_at: now + ttl }
          return :full unless store_entry(@token_buckets, key, state)

          answer
        end
      end

      def peek_token_bucket(key, policy)
        reclaim_capacity
        with_read_lock(key) do
          gate = bucket_gate(key, policy)
          gate ? gate.peek(current_time) : :full
        end
      end

      def token_bucket_retry_after(key, policy)
        with_read_lock(key) do
          gate = bucket_gate(key, policy)
          gate ? gate.retry_after(current_time) : CAPACITY_RETRY_AFTER
        end
      end

      def reset_token_bucket(key)
        with_write_lock(key) { delete_entry(@token_buckets, key) }
      end

      # No circuit breaker operations here: breaker state is owned by BreakerMachines

      # Utility operations
      def clear(pattern = nil)
        if pattern
          regex = glob_to_regexp(pattern)
          delete_where { |stored_key| stored_key.match?(regex) }
        else
          @state.clear_all
        end
      end

      def reset_key(key)
        delete_where { |stored_key| owned_by?(stored_key, key) }
      end

      def healthy?
        true
      end

      def shutdown
        @state.shutdown!
        @cleanup_thread&.join(SHUTDOWN_GRACE)
        @cleanup_thread&.kill
        @cleanup_thread = nil
        ObjectSpace.undefine_finalizer(self)
      end

      private

      def delete_where
        @state.stores.each do |store|
          store.keys.each do |stored_key|
            with_write_lock(stored_key) { delete_entry(store, stored_key) } if yield(stored_key)
          end
        end
      end

      def store_entry(store, key, value)
        @state.store_entry(store, key, value)
      end

      def delete_entry(store, key)
        @state.delete_entry(store, key)
      end

      def capacity_available?(store, key)
        @state.capacity_available?(store, key)
      end

      # The key's gate, or nil when it is untracked and the store is full.
      def gcra_gate(key, policy)
        entry = @gcra_states[key]
        return Gcra.restored(policy, entry[:tat]) if entry

        Gcra.new(policy) if capacity_available?(@gcra_states, key)
      end

      def bucket_gate(key, policy)
        entry = @token_buckets[key]
        return restored_bucket(policy, entry) if entry

        TokenBucket.new(policy) if capacity_available?(@token_buckets, key)
      end

      # A capacity lowered since the key was stored keeps at most a full
      # bucket.
      def restored_bucket(policy, entry)
        TokenBucket.restored(policy, [entry[:tokens], policy.capacity].min, entry[:refilled_at])
      end

      # Run before taking any striped lock. At saturation, attempt expiry
      # cleanup at most once per second, even with auto_cleanup disabled.
      # Rejected identity sprays must not trigger a full scan on every call.
      def reclaim_capacity
        return unless @state.saturated?
        return unless @capacity_cleanup_lock.try_lock

        begin
          now = current_time
          return if @next_capacity_cleanup_at && now < @next_capacity_cleanup_at

          @next_capacity_cleanup_at = now + CAPACITY_RETRY_AFTER
          clean_expired_entries
        ensure
          @capacity_cleanup_lock.unlock
        end
      end

      def with_read_lock(key, &block)
        @state.with_read_lock(key, &block)
      end

      def with_write_lock(key, &block)
        @state.with_write_lock(key, &block)
      end

      def clean_expired_entries
        @state.clean_expired_entries
      end

      # Holds every map, lock and counter the cleanup worker sweeps.
      class State
        attr_reader :counters, :gcra_states, :token_buckets

        def initialize(max_keys:, lock_pool_size:, cleanup_interval:)
          @max_keys = max_keys
          @cleanup_interval = cleanup_interval
          @stored_keys = 0
          @capacity_lock = Mutex.new
          @counters = Concurrent::Hash.new
          @gcra_states = Concurrent::Hash.new
          @token_buckets = Concurrent::Hash.new

          # Use a striped lock pattern - pool of locks for fine-grained concurrency
          @lock_pool_size = lock_pool_size
          @locks = Array.new(lock_pool_size) { Concurrent::ReadWriteLock.new }
          @shutdown = false
        end

        def start_cleanup_thread
          Thread.new do
            loop do
              break if @shutdown

              sleep Rational(@cleanup_interval, NS_PER_SECOND)
              break if @shutdown

              clean_expired_entries
            end
          end
        end

        def shutdown!
          @shutdown = true
        end

        def stores
          [@counters, @gcra_states, @token_buckets]
        end

        def stored_keys
          @capacity_lock.synchronize { @stored_keys }
        end

        def saturated?
          @capacity_lock.synchronize { @stored_keys >= @max_keys }
        end

        def with_read_lock(key, &block)
          lock_for(key).with_read_lock(&block)
        end

        def with_write_lock(key, &block)
          lock_for(key).with_write_lock(&block)
        end

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

        def clear_all
          @capacity_lock.synchronize do
            @counters.clear
            @gcra_states.clear
            @token_buckets.clear
            @stored_keys = 0
          end
        end

        def clean_expired_entries
          now = ThrottleMachines.monotonic_time

          stores.each do |store|
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

        private

        def lock_for(key)
          # Hash key to determine which lock to use
          index = key.hash.abs % @lock_pool_size
          @locks[index]
        end
      end
    end
  end
end
