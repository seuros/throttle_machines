# frozen_string_literal: true

module ThrottleMachines
  # Events emitted through ActiveSupport::Notifications (or any backend
  # answering `instrument`). Periods, waits and durations in payloads are
  # Integer nanoseconds.
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

      # Whether events are published: callers whose payload costs a storage
      # read ask first, so a silenced gem pays nothing for it.
      def active?
        enabled && !backend.nil?
      end

      def instrument(event_name, payload = {}, &block)
        unless active?
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
  end
end
