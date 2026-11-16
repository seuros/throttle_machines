# frozen_string_literal: true

module ThrottleMachines
  module Storage
    # Fixed windows in an ActiveSupport cache, aligned to the wall-clock
    # epoch so every process sharing the cache counts the same window.
    class Cache < Base
      # The wildcard a caller's pattern keeps; everything else is a literal.
      PATTERN_SPECIALS = /[?\[\]\\]/

      def initialize(options = {})
        super
        @cache = options[:cache_store] || (defined?(Rails) && Rails.cache)
        raise ArgumentError, 'Cache storage requires a cache_store outside Rails' unless @cache

        @prefix = options[:prefix] || 'throttle_machines'
        @fail_closed = options.fetch(:fail_closed, false)
      end

      def increment_counter(key, window, amount = 1)
        expires_in = window.ceildiv(NS_PER_SECOND) + 1
        count = @cache.increment(window_key(key, window), amount, expires_in: expires_in)
        count || (@fail_closed ? UNTRACKED : 0)
      end

      def get_counter(key, window)
        @cache.read(window_key(key, window), raw: true).to_i
      end

      # Integer nanoseconds until the current window ends.
      def get_counter_ttl(_key, window)
        window = positive_window(window)
        window - (wall_time % window)
      end

      def reset_counter(key, window)
        @cache.delete(window_key(key, window))
      end

      def clear(pattern = nil)
        delete_matched(matcher_for("#{@prefix}#{KEY_SEPARATOR}#{pattern || GLOB_WILDCARD}"))
      end

      # The window and the bucket index a counter was written under are unknown
      # here, so the counters go by a prefix of the key's own namespace.
      def reset_key(key)
        delete_matched(prefix_matcher("#{@prefix}#{KEY_SEPARATOR}#{key}#{KEY_SEPARATOR}"))
      end

      def healthy?
        !@cache.increment("#{@prefix}:health", 1, expires_in: 60).nil?
      rescue StandardError
        false
      end

      private

      def window_key(key, window)
        window = positive_window(window)
        "#{@prefix}:#{key}:#{window}:#{wall_time / window}"
      end

      def positive_window(window)
        raise TypeError, "window must be an Integer, got #{window.inspect}" unless window.is_a?(Integer)
        raise RangeError, "window must be positive, got #{window}" unless window.positive?

        window
      end

      def delete_matched(matcher)
        @cache.delete_matched(matcher)
      rescue NotImplementedError
        raise UnsupportedOperationError,
              "#{@cache.class} cannot delete by pattern; reset limiters individually with Limiter#reset!"
      end

      def matcher_for(glob)
        return glob.gsub(PATTERN_SPECIALS) { |char| "\\#{char}" } if @cache.respond_to?(:redis)

        Regexp.new("^#{Regexp.escape(glob).gsub(Regexp.escape(GLOB_WILDCARD), '.*')}")
      end

      def prefix_matcher(literal)
        return "#{escape_glob(literal)}#{GLOB_WILDCARD}" if @cache.respond_to?(:redis)

        # ActiveSupport only prepends a store's namespace to a `^` source.
        Regexp.new("^#{Regexp.escape(literal)}")
      end

      # Integer nanoseconds since the Unix epoch.
      def wall_time
        now = Time.now
        (now.to_i * NS_PER_SECOND) + now.nsec
      end
    end
  end
end
