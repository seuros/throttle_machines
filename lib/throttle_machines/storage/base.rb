# frozen_string_literal: true

module ThrottleMachines
  module Storage
    # Where limiters keep their state. Every instant and span is Integer
    # nanoseconds. A GCRA or token bucket check answers the calls still
    # admitted (an Integer) or a refusal Symbol, the core gate's own answer:
    # :throttled, :overflow when a GCRA admission would push its TAT past the
    # largest instant, or :full when the store cannot track another key.
    class Base
      ALGORITHM_OPERATIONS = {
        fixed_window: %i[increment_counter get_counter get_counter_ttl reset_counter],
        gcra: %i[check_gcra peek_gcra gcra_retry_after reset_gcra],
        token_bucket: %i[check_token_bucket peek_token_bucket token_bucket_retry_after reset_token_bucket]
      }.freeze

      HEALTH_KEY = 'throttle_machines:health'

      # The count a counter the store cannot track answers: past any limit.
      UNTRACKED = 2**64

      # What a backend puts between a limiter's key and the state it appends.
      KEY_SEPARATOR = ':'

      GLOB_WILDCARD = '*'
      GLOB_SPECIALS = /[*?\[\]\\]/

      def initialize(options = {})
        @options = options
      end

      def supports?(algorithm)
        operations = ALGORITHM_OPERATIONS[algorithm]
        return false unless operations

        operations.all? { |operation| self.class.instance_method(operation).owner != Base }
      end

      # Counts `amount` more calls in the `window` the key is in; answers the
      # window's count.
      def increment_counter(key, window, amount = 1)
        unsupported(:increment_counter)
      end

      def get_counter(key, window)
        unsupported(:get_counter)
      end

      # Integer nanoseconds until the key's window ends.
      def get_counter_ttl(key, window)
        unsupported(:get_counter_ttl)
      end

      def reset_counter(key, window)
        unsupported(:reset_counter)
      end

      # Admits one call under a ThrottleMachines::GcraPolicy, keeping the
      # state `ttl` past now.
      def check_gcra(key, policy, ttl)
        unsupported(:check_gcra)
      end

      def peek_gcra(key, policy)
        unsupported(:peek_gcra)
      end

      def gcra_retry_after(key, policy)
        unsupported(:gcra_retry_after)
      end

      def reset_gcra(key)
        unsupported(:reset_gcra)
      end

      # Admits one call under a ThrottleMachines::TokenBucketPolicy.
      def check_token_bucket(key, policy, ttl)
        unsupported(:check_token_bucket)
      end

      def peek_token_bucket(key, policy)
        unsupported(:peek_token_bucket)
      end

      def token_bucket_retry_after(key, policy)
        unsupported(:token_bucket_retry_after)
      end

      def reset_token_bucket(key)
        unsupported(:reset_token_bucket)
      end

      def clear(pattern = nil)
        unsupported(:clear)
      end

      # Deletes every entry this key owns, whatever algorithm wrote it.
      def reset_key(key)
        unsupported(:reset_key)
      end

      def healthy?
        get_counter(HEALTH_KEY, NS_PER_SECOND)
        true
      rescue StandardError
        false
      end

      # Runs the block for at most `timeout` nanoseconds, less when the
      # ambient deadline_machines budget is shorter.
      def with_timeout(timeout, &)
        DeadlineMachines.check!
        Timeout.timeout(Rational(DeadlineMachines.clamp_sleep(timeout), NS_PER_SECOND), &)
      end

      protected

      def owned_by?(stored_key, key)
        stored_key == key || stored_key.start_with?("#{key}#{KEY_SEPARATOR}")
      end

      def escape_glob(literal)
        literal.gsub(GLOB_SPECIALS) { |char| "\\#{char}" }
      end

      def glob_to_regexp(glob)
        Regexp.new("\\A#{Regexp.escape(glob).gsub(Regexp.escape(GLOB_WILDCARD), '.*')}\\z")
      end

      def current_time
        ThrottleMachines.monotonic_time
      end

      private

      def unsupported(operation)
        raise NotImplementedError, "#{self.class} does not implement ##{operation}"
      end
    end
  end
end
