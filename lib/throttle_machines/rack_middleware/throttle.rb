# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    class Throttle
      attr_reader :name, :limit, :period, :block, :algorithm

      def initialize(name, options, &block)
        @name = name
        @block = block

        raise ArgumentError, 'Must pass :limit option' unless options[:limit]
        raise ArgumentError, 'Must pass :period option' unless options[:period]

        @limit = options[:limit]
        @period = options[:period].to_i
        @algorithm = options[:algorithm] || :fixed_window
      end

      def matched_by?(request)
        discriminator = discriminator_for(request)

        return false unless discriminator

        key = "#{@name}:#{discriminator}"
        current_limit = limit_for(request)
        current_period = period_for(request)

        # Use ThrottleMachines limiter
        limiter = ThrottleMachines.limiter(
          key,
          limit: current_limit,
          period: current_period,
          algorithm: @algorithm
        )

        # Try to consume the request atomically
        throttled = false

        begin
          # This will either succeed and consume a request, or raise ThrottledError
          limiter.throttle!

          # If we get here, request was allowed
        rescue ThrottledError
          # Request was throttled
          throttled = true
        end

        # Get current state for instrumentation
        data = {
          discriminator: discriminator,
          count: current_limit - limiter.remaining,
          period: current_period,
          limit: current_limit,
          retry_after: limiter.retry_after
        }

        annotate_request_with_throttle_data(request, data)

        if throttled
          annotate_request_with_matched_data(request, data)
          ThrottleMachines::RackMiddleware.instrument(request)
        end

        throttled
      end

      private

      def discriminator_for(request)
        @block.call(request)
      end

      def limit_for(request)
        @limit.respond_to?(:call) ? @limit.call(request) : @limit
      end

      def period_for(request)
        @period.respond_to?(:call) ? @period.call(request) : @period
      end

      def annotate_request_with_throttle_data(request, data)
        (request.env['rack.attack.throttle_data'] ||= {})[@name] = data
      end

      def annotate_request_with_matched_data(request, data)
        request.env['rack.attack.matched'] = @name
        request.env['rack.attack.match_discriminator'] = data[:discriminator]
        request.env['rack.attack.match_type'] = :throttle
        request.env['rack.attack.match_data'] = data
      end
    end
  end
end
