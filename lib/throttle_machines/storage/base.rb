# frozen_string_literal: true

module ThrottleMachines
  module Storage
    class Base
      ALGORITHM_OPERATIONS = {
        fixed_window: %i[increment_counter get_counter get_counter_ttl reset_counter],
        gcra: %i[check_gcra_limit peek_gcra_limit reset_gcra],
        token_bucket: %i[check_token_bucket peek_token_bucket reset_token_bucket]
      }.freeze

      HEALTH_KEY = 'throttle_machines:health'

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

      # Rate limiting operations
      def increment_counter(key, window, amount = 1)
        raise NotImplementedError, "#{self.class} does not implement #increment_counter"
      end

      def get_counter(key, window)
        raise NotImplementedError, "#{self.class} does not implement #get_counter"
      end

      def get_counter_ttl(key, window)
        raise NotImplementedError, "#{self.class} does not implement #get_counter_ttl"
      end

      def reset_counter(key, window)
        raise NotImplementedError, "#{self.class} does not implement #reset_counter"
      end

      # GCRA operations (atomic)
      def check_gcra_limit(key, emission_interval, delay_tolerance, ttl)
        raise NotImplementedError, "#{self.class} does not implement #check_gcra_limit"
      end

      def peek_gcra_limit(key, emission_interval, delay_tolerance)
        raise NotImplementedError, "#{self.class} does not implement #peek_gcra_limit"
      end

      def reset_gcra(key)
        raise NotImplementedError, "#{self.class} does not implement #reset_gcra"
      end

      # Token bucket operations (atomic)
      def check_token_bucket(key, capacity, refill_rate, ttl)
        raise NotImplementedError, "#{self.class} does not implement #check_token_bucket"
      end

      def peek_token_bucket(key, capacity, refill_rate)
        raise NotImplementedError, "#{self.class} does not implement #peek_token_bucket"
      end

      def reset_token_bucket(key)
        raise NotImplementedError, "#{self.class} does not implement #reset_token_bucket"
      end

      # Utility operations
      def clear(pattern = nil)
        raise NotImplementedError, "#{self.class} does not implement #clear"
      end

      # Deletes every entry this key owns, whatever algorithm wrote it.
      def reset_key(key)
        raise NotImplementedError, "#{self.class} does not implement #reset_key"
      end

      def healthy?
        get_counter(HEALTH_KEY, 1)
        true
      rescue StandardError
        false
      end

      def with_timeout(timeout, &block)
        DeadlineMachines.check!
        Timeout.timeout(DeadlineMachines.clamp_sleep(timeout), &block)
      end

      # Rounding slack for time comparisons, in units of the clock's precision.
      # Matches the native core.
      SLACK_ULPS = 64

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

      # Times are running sums and differences of float seconds, so an
      # on-schedule arrival can miss an exact boundary by a few ulps. The slack
      # scales with the clock's magnitude.
      def rounding_slack(time)
        Float::EPSILON * SLACK_ULPS * [time.abs, 1.0].max
      end

      def gcra_allowed?(tat, now, delay_tolerance)
        tat - now <= delay_tolerance + rounding_slack(tat)
      end

      # Whether a token is available, allowing for rounding in the refill.
      def token_available?(tokens, now, refill_rate)
        tokens >= 1 - (rounding_slack(now) * refill_rate)
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
