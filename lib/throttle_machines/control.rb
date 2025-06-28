# frozen_string_literal: true

module ThrottleMachines
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
      timeout ||= within
      @rules[:breaker] = {
        failure_threshold: failures,
        timeout: timeout,
        window: within
      }
      self
    end

    def retry_on_failure(times:, backoff: :exponential, base_delay: 1, max_delay: 60)
      @rules[:retry] = {
        max_attempts: times,
        jitter: backoff,
        base_delay: base_delay,
        max_delay: max_delay
      }
      self
    end

    def call(&block)
      setup_components

      # Build execution chain: Retry -> Breaker -> Limiter -> User Code
      execution_chain = block

      # Wrap with rate limiter (innermost, checked first)
      if @limiter
        limiter_wrapped = execution_chain
        execution_chain = proc { @limiter.throttle!(&limiter_wrapped) }
      end

      # Wrap with circuit breaker
      if @breaker
        breaker_wrapped = execution_chain
        execution_chain = proc { @breaker.call(&breaker_wrapped) }
      end

      # Wrap with retry logic (outermost, handles all failures)
      if @retrier
        retry_wrapped = execution_chain
        execution_chain = proc { @retrier.call(&retry_wrapped) }
      end

      execution_chain.call
    end

    private

    def setup_components
      if @rules[:limit] && !@limiter
        @limiter = ThrottleMachines.limiter(@key,
                                            limit: @rules[:limit][:rate],
                                            period: @rules[:limit][:period],
                                            algorithm: @rules[:limit][:algorithm])
      end

      if @rules[:breaker] && !@breaker
        @breaker = BreakerMachines::Circuit.new(
          @key,
          failure_threshold: @rules[:breaker][:failure_threshold],
          failure_window: @rules[:breaker][:window],
          reset_timeout: @rules[:breaker][:timeout]
        )
      end

      return unless @rules[:retry] && !@retrier

      # Use ChronoMachines for retry functionality
      policy_options = {
        max_attempts: @rules[:retry][:max_attempts],
        base_delay: @rules[:retry][:base_delay],
        max_delay: @rules[:retry][:max_delay],
        jitter_factor: @rules[:retry][:jitter] == :exponential ? 1.0 : 0.0
      }
      @retrier = ChronoMachines::Executor.new(policy_options)
    end
  end
end
