# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    class Track
      attr_reader :name, :block, :limit, :period

      def initialize(name, options = {}, &block)
        @name = name
        @block = block
        @limit = options[:limit]
        @period = options[:period]
      end

      def matched_by?(request)
        discriminator = @block.call(request)
        return false unless discriminator

        # Track is just instrumentation without blocking
        data = {
          discriminator: discriminator
        }

        # If limit and period are provided, track the count
        if @limit && @period
          key = "track:#{@name}:#{discriminator}"
          limiter = ThrottleMachines.limiter(
            key,
            limit: @limit,
            period: @period,
            algorithm: :fixed_window
          )

          # Just check, don't consume
          data[:count] = @limit - limiter.remaining
          data[:limit] = @limit
          data[:period] = @period
        end

        request.env['rack.attack.matched'] = @name
        request.env['rack.attack.match_type'] = :track
        request.env['rack.attack.match_discriminator'] = discriminator
        request.env['rack.attack.match_data'] = data

        ThrottleMachines::RackMiddleware.instrument(request)

        false # Track never blocks
      end
    end
  end
end
