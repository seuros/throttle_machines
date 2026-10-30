# frozen_string_literal: true

module ThrottleMachines
  module Storage
    class Cache < Base
      GLOB_SPECIALS = /[?\[\]\\]/

      def initialize(options = {})
        super
        @cache = options[:cache_store] || (defined?(Rails) && Rails.cache)
        raise ArgumentError, 'Cache storage requires a cache_store outside Rails' unless @cache

        @prefix = options[:prefix] || 'throttle_machines'
        @fail_closed = options.fetch(:fail_closed, false)
      end

      def increment_counter(key, window, amount = 1)
        count = @cache.increment(window_key(key, window), amount, expires_in: window.to_f.ceil + 1)
        count || (@fail_closed ? Float::INFINITY : 0)
      end

      def get_counter(key, window)
        @cache.read(window_key(key, window), raw: true).to_i
      end

      def get_counter_ttl(_key, window)
        window = positive_window(window)
        window - (wall_time % window)
      end

      def reset_counter(key, window)
        @cache.delete(window_key(key, window))
      end

      def clear(pattern = nil)
        @cache.delete_matched(matcher_for("#{@prefix}:#{pattern || '*'}"))
      rescue NotImplementedError
        raise UnsupportedOperationError,
              "#{@cache.class} cannot delete by pattern; reset limiters individually with Limiter#reset!"
      end

      def healthy?
        !@cache.increment("#{@prefix}:health", 1, expires_in: 60).nil?
      rescue StandardError
        false
      end

      private

      def window_key(key, window)
        window = positive_window(window)
        "#{@prefix}:#{key}:#{window}:#{(wall_time / window).floor}"
      end

      def positive_window(window)
        window = window.to_f
        raise ArgumentError, "window must be positive, got #{window}" unless window.positive?

        window
      end

      def matcher_for(glob)
        return glob.gsub(GLOB_SPECIALS) { |char| "\\#{char}" } if @cache.respond_to?(:redis)

        Regexp.new("^#{Regexp.escape(glob).gsub('\*', '.*')}")
      end

      def wall_time
        Time.now.to_f
      end
    end
  end
end
