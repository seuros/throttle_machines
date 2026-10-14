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

      # Utility operations
      def clear(pattern = nil)
        raise NotImplementedError
      end

      def healthy?
        raise NotImplementedError
      end

      def with_timeout(timeout, &block)
        Timeout.timeout(timeout, &block)
      rescue Timeout::Error
        nil
      end

      # Rounding slack for GCRA comparisons, in units of the TAT's precision.
      # Matches the native core.
      GCRA_SLACK_ULPS = 64

      protected

      # The TAT is a running sum of emission intervals, so an on-schedule
      # arrival can overshoot the tolerance by a few ulps. The slack scales
      # with the clock's magnitude.
      def gcra_allowed?(tat, now, delay_tolerance)
        tat - now <= delay_tolerance + (Float::EPSILON * GCRA_SLACK_ULPS * [tat.abs, 1.0].max)
      end

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
