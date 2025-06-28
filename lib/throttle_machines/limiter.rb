# frozen_string_literal: true

module ThrottleMachines
  class Limiter
    attr_reader :key, :limit, :period, :algorithm, :storage

    def initialize(key, limit:, period:, algorithm: :fixed_window, storage: nil)
      @key = key
      @limit = limit
      @period = period
      @algorithm = algorithm
      @storage = storage || ThrottleMachines.storage
    end

    def allow?
      allowed = case @algorithm
                when :fixed_window
                  # Don't increment here, just check
                  count = @storage.get_counter(@key, @period)
                  count < @limit
                when :gcra
                  result = @storage.peek_gcra_limit(
                    @key,
                    @period.to_f / @limit,  # emission_interval
                    0                       # delay_tolerance (no burst)
                  )
                  result[:allowed]
                when :token_bucket
                  result = @storage.peek_token_bucket(
                    @key,
                    @limit,                 # capacity
                    @limit.to_f / @period   # refill_rate
                  )
                  result[:allowed]
                else
                  raise ArgumentError, "Unknown algorithm: #{@algorithm}"
                end

      # Instrument the check
      Instrumentation.rate_limit_checked(self, allowed: allowed, remaining: nil)

      allowed
    end

    def throttle!
      case @algorithm
      when :fixed_window
        # Increment and check atomically
        count = @storage.increment_counter(@key, @period)
        if count > @limit
          Instrumentation.rate_limit_throttled(self, retry_after: retry_after)
          raise ThrottledError, self
        end
      when :gcra
        result = @storage.check_gcra_limit(
          @key,
          @period.to_f / @limit,  # emission_interval
          0,                      # delay_tolerance (no burst)
          (@period * 2).to_i      # ttl
        )
        unless result[:allowed]
          Instrumentation.rate_limit_throttled(self, retry_after: retry_after)
          raise ThrottledError, self
        end
      when :token_bucket
        result = @storage.check_token_bucket(
          @key,
          @limit,                 # capacity
          @limit.to_f / @period,  # refill_rate
          (@period * 2).to_i      # ttl
        )
        unless result[:allowed]
          Instrumentation.rate_limit_throttled(self, retry_after: retry_after)
          raise ThrottledError, self
        end
      else
        raise ArgumentError, "Unknown algorithm: #{@algorithm}"
      end

      # If we get here, the request was allowed
      # Calculate remaining after the operation
      remaining_count = begin
        remaining
      rescue StandardError
        nil
      end
      Instrumentation.rate_limit_allowed(self, remaining: remaining_count)

      yield if block_given?
    end

    def reset!
      case @algorithm
      when :fixed_window
        @storage.reset_counter(@key, @period)
      else
        @storage.clear("#{@key}*")
      end
    end

    def remaining
      case @algorithm
      when :fixed_window
        count = @storage.get_counter(@key, @period)
        [@limit - count, 0].max
      when :gcra
        # GCRA doesn't have a simple "remaining" count
        # Just return 1 or 0 based on current state
        result = @storage.peek_gcra_limit(
          @key,
          @period.to_f / @limit,
          0
        )
        result[:allowed] ? 1 : 0
      when :token_bucket
        result = @storage.peek_token_bucket(
          @key,
          @limit,
          @limit.to_f / @period
        )
        result[:tokens_remaining].to_i
      else
        0
      end
    end

    def retry_after
      case @algorithm
      when :fixed_window
        count = @storage.get_counter(@key, @period)
        if count >= @limit
          # Return the actual time remaining in the current window
          @storage.get_counter_ttl(@key, @period)
        else
          0
        end
      when :gcra
        result = @storage.peek_gcra_limit(
          @key,
          @period.to_f / @limit,
          0
        )
        result[:retry_after]
      when :token_bucket
        result = @storage.peek_token_bucket(
          @key,
          @limit,
          @limit.to_f / @period
        )
        result[:retry_after]
      else
        0
      end
    end

    def to_h
      {
        key: @key,
        limit: @limit,
        period: @period,
        algorithm: @algorithm,
        remaining: remaining,
        retry_after: retry_after
      }
    end
  end
end
