# frozen_string_literal: true

module ThrottleMachines
  # Instrumentation module for emitting events via ActiveSupport::Notifications
  module Instrumentation
    class << self
      attr_writer :enabled, :backend

      def enabled
        @enabled = true if @enabled.nil?
        @enabled
      end

      def backend
        @backend ||= ActiveSupport::Notifications
      end

      def instrument(event_name, payload = {}, &block)
        if !enabled || backend.nil?
          return yield if block_given?

          return
        end

        full_event_name = "#{event_name}.throttle_machines"
        backend.instrument(full_event_name, payload, &block)
      end

      # Convenience methods for common events

      # Rate limiter events
      def rate_limit_checked(limiter, allowed:, remaining: nil)
        payload = {
          key: limiter.key,
          limit: limiter.limit,
          period: limiter.period,
          algorithm: limiter.algorithm,
          allowed: allowed,
          remaining: remaining
        }
        instrument('rate_limit.checked', payload)
      end

      def rate_limit_allowed(limiter, remaining: nil)
        payload = {
          key: limiter.key,
          limit: limiter.limit,
          period: limiter.period,
          algorithm: limiter.algorithm,
          remaining: remaining
        }
        instrument('rate_limit.allowed', payload)
      end

      def rate_limit_throttled(limiter, retry_after: nil)
        payload = {
          key: limiter.key,
          limit: limiter.limit,
          period: limiter.period,
          algorithm: limiter.algorithm,
          retry_after: retry_after
        }
        instrument('rate_limit.throttled', payload)
      end

      # Circuit breaker events
      def circuit_opened(breaker, failure_count:)
        payload = {
          key: (breaker.respond_to?(:name) ? breaker.name : breaker.to_s),
          failure_threshold: (breaker.respond_to?(:configuration) ? breaker.configuration[:failure_threshold] : nil),
          timeout: (breaker.respond_to?(:configuration) ? breaker.configuration[:reset_timeout] : nil),
          failure_count: failure_count
        }
        instrument('circuit_breaker.opened', payload)
      end

      def circuit_closed(breaker)
        payload = {
          key: (breaker.respond_to?(:name) ? breaker.name : breaker.to_s),
          failure_threshold: (breaker.respond_to?(:configuration) ? breaker.configuration[:failure_threshold] : nil),
          timeout: (breaker.respond_to?(:configuration) ? breaker.configuration[:reset_timeout] : nil)
        }
        instrument('circuit_breaker.closed', payload)
      end

      def circuit_half_opened(breaker)
        payload = {
          key: (breaker.respond_to?(:name) ? breaker.name : breaker.to_s),
          failure_threshold: (breaker.respond_to?(:configuration) ? breaker.configuration[:failure_threshold] : nil),
          timeout: (breaker.respond_to?(:configuration) ? breaker.configuration[:reset_timeout] : nil),
          half_open_requests: (breaker.respond_to?(:configuration) ? breaker.configuration[:half_open_calls] : nil)
        }
        instrument('circuit_breaker.half_opened', payload)
      end

      def circuit_success(breaker)
        payload = {
          key: (breaker.respond_to?(:name) ? breaker.name : breaker.to_s),
          state: (breaker.respond_to?(:to_h) ? breaker.to_h[:state] : nil)
        }
        instrument('circuit_breaker.success', payload)
      end

      def circuit_failure(breaker, error: nil)
        payload = {
          key: (breaker.respond_to?(:name) ? breaker.name : breaker.to_s),
          state: (breaker.respond_to?(:to_h) ? breaker.to_h[:state] : nil),
          error_class: error&.class&.name,
          error_message: error&.message
        }
        instrument('circuit_breaker.failure', payload)
      end

      def circuit_rejected(breaker)
        payload = {
          key: (breaker.respond_to?(:name) ? breaker.name : breaker.to_s),
          failure_threshold: (breaker.respond_to?(:configuration) ? breaker.configuration[:failure_threshold] : nil),
          timeout: (breaker.respond_to?(:configuration) ? breaker.configuration[:reset_timeout] : nil)
        }
        instrument('circuit_breaker.rejected', payload)
      end

      # Cascade events
      def cascade_triggered(primary_key, cascaded_key)
        payload = {
          primary_key: primary_key,
          cascaded_key: cascaded_key
        }
        instrument('cascade.triggered', payload)
      end

      # Hedged request events
      def hedged_request_started(request_id, attempts:)
        payload = {
          request_id: request_id,
          max_attempts: attempts
        }
        instrument('hedged_request.started', payload)
      end

      def hedged_request_winner(request_id, attempt:, duration:)
        payload = {
          request_id: request_id,
          winning_attempt: attempt,
          duration: duration
        }
        instrument('hedged_request.winner', payload)
      end
    end

    # Null backend for when ActiveSupport::Notifications is not available
    class NullBackend
      def instrument(_name, _payload = {})
        yield if block_given?
      end
    end
  end
end
