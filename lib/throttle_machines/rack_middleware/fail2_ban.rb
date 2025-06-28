# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    class Fail2Ban
      attr_reader :name, :maxretry, :findtime, :bantime, :block

      def initialize(name, options, &block)
        @name = name
        @block = block

        @maxretry = options[:maxretry] || 5
        @findtime = options[:findtime] || 60
        @bantime = options[:bantime] || 300
      end

      def banned?(request)
        discriminator = discriminator_for(request)
        return false unless discriminator

        key = "fail2ban:#{@name}:#{discriminator}"

        # Use circuit breaker to track failures
        breaker = ThrottleMachines::Breaker.new(
          key,
          failure_threshold: @maxretry,
          timeout: @bantime,
          storage: ThrottleMachines.storage
        )

        # Check if circuit is open (banned)
        if breaker.open?
          # Get breaker state for instrumentation
          state = breaker.to_h

          request.env['rack.attack.matched'] = @name
          request.env['rack.attack.match_type'] = :fail2ban
          request.env['rack.attack.match_discriminator'] = discriminator
          request.env['rack.attack.match_data'] = {
            discriminator: discriminator,
            maxretry: @maxretry,
            findtime: @findtime,
            bantime: @bantime,
            failures: state[:failure_count],
            time_until_unban: state[:time_until_retry]
          }

          ThrottleMachines::RackMiddleware.instrument(request)
          true
        else
          false
        end
      end

      def count(request)
        discriminator = discriminator_for(request)
        return unless discriminator

        key = "fail2ban:#{@name}:#{discriminator}"

        # Use the breaker to record a failure if block returns true
        return unless yield

        breaker = ThrottleMachines::Breaker.new(
          key,
          failure_threshold: @maxretry,
          timeout: @bantime,
          storage: ThrottleMachines.storage
        )

        # Record failure by trying to call through the breaker
        # and letting it fail
        begin
          breaker.call { raise 'Fail2Ban failure' }
        rescue StandardError
          # Expected - this records the failure
        end
      end

      private

      def discriminator_for(request)
        @block.call(request)
      end
    end
  end
end
