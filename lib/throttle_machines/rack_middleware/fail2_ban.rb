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

        # Use a globally managed BreakerMachines circuit as the ban mechanism
        breaker = BreakerMachines::Registry.instance.get_or_create_dynamic_circuit(
          key,
          self,
          failure_threshold: @maxretry,
          failure_window: @findtime,
          reset_timeout: @bantime
        )

        # Check if circuit is open (banned)
        if breaker.open?
          stats = breaker.stats
          now = BreakerMachines.monotonic_time
          time_until_unban = if stats.opened_at
                               remaining = @bantime - (now - stats.opened_at)
                               remaining.positive? ? remaining : 0
                             else
                               @bantime
                             end

          request.env['rack.attack.matched'] = @name
          request.env['rack.attack.match_type'] = :fail2ban
          request.env['rack.attack.match_discriminator'] = discriminator
          request.env['rack.attack.match_data'] = {
            discriminator: discriminator,
            maxretry: @maxretry,
            findtime: @findtime,
            bantime: @bantime,
            failures: stats.failure_count,
            time_until_unban: time_until_unban
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

        breaker = BreakerMachines::Registry.instance.get_or_create_dynamic_circuit(
          key,
          self,
          failure_threshold: @maxretry,
          failure_window: @findtime,
          reset_timeout: @bantime
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
