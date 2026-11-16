# frozen_string_literal: true

module ThrottleMachines
  # `limit` calls per `period` (Integer nanoseconds) for one key, decided by
  # `algorithm` over shared storage. A runtime object: its keywords have no
  # core counterpart. Every answer in time is Integer nanoseconds.
  class Limiter
    ALGORITHMS = %i[fixed_window gcra token_bucket].freeze

    attr_reader :key, :limit, :period, :algorithm, :storage, :policy

    def initialize(key, limit:, period:, algorithm: :fixed_window, storage: nil)
      @key = key
      @limit = positive(limit, 'limit')
      @period = positive(period, 'period')
      @algorithm = algorithm
      @storage = storage || ThrottleMachines.storage
      validate_algorithm!
      @policy = build_policy
      freeze
    end

    # Whether a call would be admitted now, consuming nothing.
    def allow?
      allowed = peek.is_a?(Integer)
      Instrumentation.rate_limit_checked(self, allowed: allowed, remaining: nil)
      allowed
    end

    # Admits one call or raises ThrottledError, then runs the block. An
    # admission reports the count the check itself answered, which equals
    # `remaining` at that instant (test/throttle_machines/remaining_parity_test.rb)
    # and cannot race another caller; a refusal's `retry_after` costs a
    # storage read, made only while instrumentation is active.
    def throttle!
      left = check
      unless left.is_a?(Integer)
        Instrumentation.rate_limit_throttled(self, retry_after: retry_after) if Instrumentation.active?
        raise ThrottledError, self
      end

      Instrumentation.rate_limit_allowed(self, remaining: left) if Instrumentation.active?
      yield if block_given?
    end

    def reset!
      case @algorithm
      when :fixed_window then @storage.reset_counter(@key, @period)
      when :gcra then @storage.reset_gcra(@key)
      when :token_bucket then @storage.reset_token_bucket(@key)
      end
    end

    # Calls still admitted now: the window's or bucket's count; for GCRA, the
    # calls its burst admits back to back (one without a burst).
    def remaining
      answer = peek
      answer.is_a?(Integer) ? answer : 0
    end

    # Integer nanoseconds until a call is admitted; zero when one is now.
    def retry_after
      case @algorithm
      when :fixed_window
        @storage.get_counter(@key, @period) >= @limit ? @storage.get_counter_ttl(@key, @period) : 0
      when :gcra then @storage.gcra_retry_after(@key, @policy)
      when :token_bucket then @storage.token_bucket_retry_after(@key, @policy)
      end
    end

    def to_h
      { key: @key, limit: @limit, period: @period, algorithm: @algorithm, remaining: remaining,
        retry_after: retry_after }
    end

    private

    # Integer calls left after this admission, or a refusal Symbol.
    def check
      case @algorithm
      when :fixed_window
        count = @storage.increment_counter(@key, @period)
        count <= @limit ? @limit - count : :throttled
      when :gcra then @storage.check_gcra(@key, @policy, @period * 2)
      when :token_bucket then @storage.check_token_bucket(@key, @policy, @period * 2)
      end
    end

    # Integer calls admitted now, at least one, or a refusal Symbol.
    def peek
      case @algorithm
      when :fixed_window
        count = @storage.get_counter(@key, @period)
        count < @limit ? @limit - count : :throttled
      when :gcra then @storage.peek_gcra(@key, @policy)
      when :token_bucket then @storage.peek_token_bucket(@key, @policy)
      end
    end

    def build_policy
      case @algorithm
      when :fixed_window then FixedWindowPolicy.new(@period, @limit)
      when :gcra then GcraPolicy.per(@period, @limit, 1)
      when :token_bucket then TokenBucketPolicy.per(@period, @limit)
      end
    end

    def positive(value, name)
      raise TypeError, "#{name} must be an Integer, got #{value.inspect}" unless value.is_a?(Integer)
      raise RangeError, "#{name} must be positive, got #{value}" unless value.positive?

      value
    end

    def validate_algorithm!
      raise RangeError, "Unknown algorithm: #{@algorithm.inspect}" unless ALGORITHMS.include?(@algorithm)
      return unless @storage.respond_to?(:supports?)
      return if @storage.supports?(@algorithm)

      raise RangeError, "#{@storage.class} does not support the #{@algorithm.inspect} algorithm"
    end
  end
end
