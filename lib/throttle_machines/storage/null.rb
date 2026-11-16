# frozen_string_literal: true

module ThrottleMachines
  module Storage
    # Admits everything and keeps nothing: every check answers the policy's
    # full allowance, every wait is zero.
    class Null < Base
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

      def check_gcra(_key, policy, _ttl)
        Gcra.new(policy).peek(0) - 1
      end

      def peek_gcra(_key, policy)
        Gcra.new(policy).peek(0)
      end

      def gcra_retry_after(_key, _policy)
        0
      end

      def reset_gcra(_key)
        true
      end

      def check_token_bucket(_key, policy, _ttl)
        policy.capacity - 1
      end

      def peek_token_bucket(_key, policy)
        policy.capacity
      end

      def token_bucket_retry_after(_key, _policy)
        0
      end

      def reset_token_bucket(_key)
        true
      end

      def clear(_pattern = nil)
        true
      end

      def reset_key(_key)
        true
      end

      def healthy?
        true
      end
    end
  end
end
