# frozen_string_literal: true

module ThrottleMachines
  module Storage
    class Base
      def initialize(options = {})
        @options = options
      end

      # Rate limiting operations
      def increment_counter(key, window, amount = 1)
        raise NotImplementedError
      end

      def get_counter(key, window)
        raise NotImplementedError
      end

      def get_counter_ttl(key, window)
        raise NotImplementedError
      end

      def reset_counter(key, window)
        raise NotImplementedError
      end

      # GCRA operations (atomic)
      def check_gcra_limit(key, emission_interval, delay_tolerance, ttl)
        raise NotImplementedError
      end

      def peek_gcra_limit(key, emission_interval, delay_tolerance)
        raise NotImplementedError
      end

      # Token bucket operations (atomic)
      def check_token_bucket(key, capacity, refill_rate, ttl)
        raise NotImplementedError
      end

      def peek_token_bucket(key, capacity, refill_rate)
        raise NotImplementedError
      end

      # Circuit breaker operations
      def get_breaker_state(key)
        raise NotImplementedError
      end

      def record_breaker_success(key, timeout, half_open_requests = 1)
        raise NotImplementedError
      end

      def record_breaker_failure(key, threshold, timeout)
        raise NotImplementedError
      end

      def trip_breaker(key, timeout)
        raise NotImplementedError
      end

      def reset_breaker(key)
        raise NotImplementedError
      end

      # Utility operations
      def clear(pattern = nil)
        raise NotImplementedError
      end

      def healthy?
        raise NotImplementedError
      end

      def with_timeout(timeout, &)
        Timeout.timeout(timeout, &)
      rescue Timeout::Error
        nil
      end

      protected

      def current_time
        # Use monotonic time for consistency with BreakerMachines
        ThrottleMachines.monotonic_time
      end

      def monotonic_time
        ThrottleMachines.monotonic_time
      end
    end
  end
end
