# frozen_string_literal: true

class ExternalApiService
  # Test control for deterministic behavior
  cattr_accessor :test_payment_behavior

  def initialize
    @payment_breaker = ThrottleMachines::Breaker.new('payment_gateway',
                                                     failure_threshold: 3,
                                                     timeout: 30)

    @email_breaker = ThrottleMachines::Breaker.new('email_service',
                                                   failure_threshold: 5,
                                                   timeout: 60)

    # Rate limiters for API calls
    @payment_limiter = ThrottleMachines.limiter('payment_api',
                                                limit: 100,
                                                period: 60,
                                                algorithm: :gcra)

    @email_limiter = ThrottleMachines.limiter('email_api',
                                              limit: 1000,
                                              period: 60)
  end

  def circuit(name)
    case name
    when :payment_gateway
      @payment_breaker
    when :email_service
      @email_breaker
    else
      raise ArgumentError, "Unknown circuit: #{name}"
    end
  end

  def process_payment(amount, _card_token)
    # Check rate limit first
    unless @payment_limiter.allowed?
      return {
        status: 'rate_limited',
        message: 'Too many payment requests',
        retry_after: @payment_limiter.ttl
      }
    end

    # Then use circuit breaker
    @payment_breaker.call do
      # Simulate payment processing with 10% failure rate
      raise 'Payment gateway timeout' if should_fail_payment?

      {
        status: 'success',
        transaction_id: SecureRandom.uuid,
        amount: amount,
        timestamp: Time.current
      }
    end
  rescue ThrottleMachines::CircuitOpenError
    {
      status: 'queued',
      message: 'Payment will be processed when service recovers',
      reference: SecureRandom.uuid
    }
  rescue StandardError => e
    {
      status: 'error',
      message: e.message
    }
  end

  def send_notification(_email, _subject, _body)
    unless @email_limiter.allowed?
      return {
        sent: false,
        error: 'Rate limited',
        retry_after: @email_limiter.ttl
      }
    end

    @email_breaker.call do
      # Simulate email sending
      raise 'SMTP connection failed' if rand > 0.95 # 5% failure rate

      {
        sent: true,
        message_id: SecureRandom.uuid,
        timestamp: Time.current
      }
    end
  rescue ThrottleMachines::CircuitOpenError
    {
      sent: false,
      queued: true,
      message: 'Email service temporarily unavailable'
    }
  end

  # Example of checking circuit state before expensive operations
  def can_process_payments?
    !@payment_breaker.open?
  end

  def service_status
    {
      payment_gateway: {
        available: !@payment_breaker.open?,
        state: @payment_breaker.state,
        failure_count: @payment_breaker.failure_count,
        rate_limit: {
          remaining: @payment_limiter.remaining,
          limit: @payment_limiter.limit
        }
      },
      email_service: {
        available: !@email_breaker.open?,
        state: @email_breaker.state,
        failure_count: @email_breaker.failure_count,
        rate_limit: {
          remaining: @email_limiter.remaining,
          limit: @email_limiter.limit
        }
      }
    }
  end

  private

  def should_fail_payment?
    # Allow tests to override this behavior
    return test_payment_behavior == :fail if test_payment_behavior

    rand > 0.9
  end
end
