# frozen_string_literal: true

require_relative 'base'
require 'concurrent'

module ThrottleMachines
  module Storage
    class Memory < Base
      def initialize(options = {})
        super
        @counters = Concurrent::Hash.new
        @gcra_states = Concurrent::Hash.new
        @token_buckets = Concurrent::Hash.new
        @breaker_states = Concurrent::Hash.new

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

        with_write_lock(window_key) do
          now = current_time
          # Fetch fresh value inside the lock to ensure consistency
          counter = @counters[window_key]

          if counter.nil? || counter[:expires_at] <= now
            # Create or reset counter atomically
            new_count = amount
            @counters[window_key] = { count: new_count, expires_at: now + window }
          else
            # Increment existing counter atomically
            new_count = counter[:count] + amount
            @counters[window_key] = { count: new_count, expires_at: counter[:expires_at] }
          end
          new_count
        end
      end

      def get_counter(key, window)
        window_key = "#{key}:#{window}"

        with_read_lock(window_key) do
          counter = @counters[window_key]
          return 0 unless counter
          return 0 if counter[:expires_at] <= current_time

          counter[:count]
        end
      end

      def get_counter_ttl(key, window)
        window_key = "#{key}:#{window}"

        with_read_lock(window_key) do
          counter = @counters[window_key]
          return 0 unless counter

          ttl = counter[:expires_at] - current_time
          [ttl, 0].max
        end
      end

      def reset_counter(key, window)
        window_key = "#{key}:#{window}"
        with_write_lock(window_key) { @counters.delete(window_key) }
      end

      # GCRA operations (atomic simulation)
      def check_gcra_limit(key, emission_interval, delay_tolerance, ttl)
        with_write_lock(key) do
          now = current_time
          state = @gcra_states[key] || { tat: 0.0 }

          tat = [state[:tat], now].max
          allow = tat - now <= delay_tolerance

          if allow
            new_tat = tat + emission_interval
            @gcra_states[key] = { tat: new_tat, expires_at: now + ttl }
          end

          {
            allowed: allow,
            retry_after: allow ? 0 : (tat - now - delay_tolerance),
            tat: tat
          }
        end
      end

      def peek_gcra_limit(key, _emission_interval, delay_tolerance)
        with_read_lock(key) do
          now = current_time
          state = @gcra_states[key] || { tat: 0.0 }

          tat = [state[:tat], now].max
          allow = tat - now <= delay_tolerance

          {
            allowed: allow,
            retry_after: allow ? 0 : (tat - now - delay_tolerance),
            tat: tat
          }
        end
      end

      # Token bucket operations (atomic simulation)
      def check_token_bucket(key, capacity, refill_rate, ttl)
        with_write_lock(key) do
          now = current_time
          bucket = @token_buckets[key] || { tokens: capacity, last_refill: now }

          # Refill tokens
          elapsed = now - bucket[:last_refill]
          tokens_to_add = elapsed * refill_rate
          bucket[:tokens] = [bucket[:tokens] + tokens_to_add, capacity].min
          bucket[:last_refill] = now

          # Check if we can consume a token
          if bucket[:tokens] >= 1
            bucket[:tokens] -= 1
            @token_buckets[key] = bucket.merge(expires_at: now + ttl)

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
        with_read_lock(key) do
          now = current_time
          bucket = @token_buckets[key] || { tokens: capacity, last_refill: now }

          # Calculate tokens without modifying state
          elapsed = now - bucket[:last_refill]
          tokens_to_add = elapsed * refill_rate
          current_tokens = [bucket[:tokens] + tokens_to_add, capacity].min

          if current_tokens >= 1
            {
              allowed: true,
              retry_after: 0,
              tokens_remaining: (current_tokens - 1).floor
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

      # Circuit breaker operations
      def get_breaker_state(key)
        # First try with read lock
        state = with_read_lock("breaker:#{key}") do
          @breaker_states[key] || { state: :closed, failures: 0, last_failure: nil }
        end

        # Check if we need to transition from open to half-open
        if state[:state] == :open && state[:opens_at] && current_time >= state[:opens_at]
          # Release read lock and acquire write lock
          with_write_lock("breaker:#{key}") do
            # Re-check condition after acquiring write lock
            current_state = @breaker_states[key]
            if current_state && current_state[:state] == :open && current_state[:opens_at] && current_time >= current_state[:opens_at]
              @breaker_states[key] = current_state.merge(
                state: :half_open,
                half_open_attempts: 0
              )
            end
            @breaker_states[key] || { state: :closed, failures: 0, last_failure: nil }
          end
        else
          state
        end
      end

      def record_breaker_success(key, _timeout, half_open_requests = 1)
        with_write_lock("breaker:#{key}") do
          state = @breaker_states[key]
          return unless state

          case state[:state]
          when :half_open
            attempts = (state[:half_open_attempts] || 0) + 1
            if attempts >= half_open_requests
              @breaker_states.delete(key)
            else
              @breaker_states[key] = state.merge(half_open_attempts: attempts)
            end
          when :closed
            # Reset failure count on success
            @breaker_states[key] = state.merge(failures: 0) if state[:failures].positive?
          end
        end
      end

      def record_breaker_failure(key, threshold, timeout)
        with_write_lock("breaker:#{key}") do
          state = @breaker_states[key] || { state: :closed, failures: 0 }
          now = current_time

          case state[:state]
          when :closed
            failures = state[:failures] + 1
            @breaker_states[key] = if failures >= threshold
                                     {
                                       state: :open,
                                       failures: failures,
                                       last_failure: now,
                                       opens_at: now + timeout
                                     }
                                   else
                                     state.merge(failures: failures, last_failure: now)
                                   end
          when :half_open
            @breaker_states[key] = {
              state: :open,
              failures: state[:failures],
              last_failure: now,
              opens_at: now + timeout
            }
          end

          @breaker_states[key]
        end
      end

      def trip_breaker(key, timeout)
        with_write_lock("breaker:#{key}") do
          now = current_time
          @breaker_states[key] = {
            state: :open,
            failures: 0,
            last_failure: now,
            opens_at: now + timeout
          }
        end
      end

      def reset_breaker(key)
        with_write_lock("breaker:#{key}") { @breaker_states.delete(key) }
      end

      # Utility operations
      def clear(pattern = nil)
        if pattern
          regex = Regexp.new(pattern.gsub('*', '.*'))

          # Clear matching keys from all stores
          [@counters, @gcra_states, @token_buckets, @breaker_states].each do |store|
            store.each_key do |k|
              store.delete(k) if k&.match?(regex)
            end
          end
        else
          @counters.clear
          @gcra_states.clear
          @token_buckets.clear
          @breaker_states.clear
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

      def with_read_lock(key, &)
        lock_for(key).with_read_lock(&)
      end

      def with_write_lock(key, &)
        lock_for(key).with_write_lock(&)
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

        # Clean expired counters
        @counters.each_pair do |key, data|
          with_write_lock(key) { @counters.delete(key) } if data[:expires_at] && data[:expires_at] <= now
        end

        # Clean expired GCRA states
        @gcra_states.each_pair do |key, data|
          with_write_lock(key) { @gcra_states.delete(key) } if data[:expires_at] && data[:expires_at] <= now
        end

        # Clean expired token buckets
        @token_buckets.each_pair do |key, data|
          with_write_lock(key) { @token_buckets.delete(key) } if data[:expires_at] && data[:expires_at] <= now
        end

        # Clean closed breaker states and expired open states
        @breaker_states.each_pair do |key, data|
          should_delete = false

          # Clean closed states that have been idle
          should_delete = true if data[:state] == :closed && data[:failures].zero?

          # Clean expired open states (older than 2x timeout)
          if data[:opens_at] && now > data[:opens_at] + ((data[:opens_at] - (data[:last_failure] || now)) * 2)
            should_delete = true
          end

          with_write_lock("breaker:#{key}") { @breaker_states.delete(key) } if should_delete
        end
      rescue StandardError => e
        # Log error but don't crash cleanup thread
        warn "ThrottleMachines: Cleanup error: #{e.message}"
      end
    end
  end
end
