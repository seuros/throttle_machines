# frozen_string_literal: true

module ThrottleMachines
  module Storage
    class Null < Base
      # Rate limiting operations
      def increment_counter(_key, _window, _amount = 1)
        0
      end

      def get_counter(_key, _window)
        0
      end

      def get_counter_ttl(_key, _window)
        0
      end

      def reset_counter(_key, _window)
        true
      end

      # GCRA operations
      def check_gcra_limit(_key, _emission_interval, _delay_tolerance, _ttl)
        {
          allowed: true,
          retry_after: 0,
          tat: 0
        }
      end

      def peek_gcra_limit(_key, _emission_interval, _delay_tolerance)
        {
          allowed: true,
          retry_after: 0,
          tat: 0
        }
      end

      # Token bucket operations
      def check_token_bucket(_key, capacity, _refill_rate, _ttl)
        {
          allowed: true,
          retry_after: 0,
          tokens_remaining: capacity
        }
      end

      def peek_token_bucket(_key, capacity, _refill_rate)
        {
          allowed: true,
          retry_after: 0,
          tokens_remaining: capacity
        }
      end

      # Utility operations
      def clear(_pattern = nil)
        true
      end

      def healthy?
        true
      end
    end
  end
end
