# frozen_string_literal: true

module ThrottleMachines
  # Composes a rate limit, a circuit breaker and a retry around a block:
  # retry outermost, then the breaker, then the limiter. Spans are Integer
  # nanoseconds.
  class Control
    attr_reader :key, :limiter, :breaker, :retrier

    def initialize(key)
      @key = key
      @rules = {}
    end

    def limit(rate:, per:, algorithm: :gcra)
      @rules[:limit] = { rate: rate, period: per, algorithm: algorithm }
      self
    end

    def break_on(failures:, within:, timeout: nil)
      @rules[:breaker] = { failure_threshold: failures, timeout: timeout || within, window: within }
      self
    end

    # Retries through ChronoMachines: a backoff shape (Exponential, Constant
    # or Fibonacci, spans in Integer nanoseconds) and the attempt cap, as
    # ChronoMachines::Executor takes them, then its runtime keywords.
    def retry_on_failure(strategy, max_attempts, **runtime)
      @rules[:retry] = [strategy, max_attempts, runtime]
      self
    end

    def call(&block)
      setup_components

      chain = block
      if @limiter
        limited = chain
        chain = proc { @limiter.throttle!(&limited) }
      end
      if @breaker
        guarded = chain
        chain = proc { @breaker.call(&guarded) }
      end
      if @retrier
        retried = chain
        chain = proc { @retrier.call(&retried) }
      end
      chain.call
    end

    private

    def setup_components
      if @rules[:limit] && !@limiter
        rule = @rules[:limit]
        @limiter = ThrottleMachines.limiter(@key, limit: rule[:rate], period: rule[:period],
                                                  algorithm: rule[:algorithm])
      end

      if @rules[:breaker] && !@breaker
        rule = @rules[:breaker]
        @breaker = BreakerMachines::Circuit.new(
          @key, Breakers.policy(rule[:failure_threshold], rule[:window], rule[:timeout]),
          exceptions: [Breakers::Failure]
        )
      end

      return unless @rules[:retry] && !@retrier

      strategy, max_attempts, runtime = @rules[:retry]
      @retrier = ChronoMachines::Executor.new(strategy, max_attempts, **runtime)
    end
  end
end
