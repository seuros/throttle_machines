# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    class Fail2Ban < BanFilter
      def banned?(request)
        discriminator = discriminator_for(request)
        return false unless discriminator

        key = "fail2ban:#{@name}:#{discriminator}"

        # Use a globally managed BreakerMachines circuit as the ban mechanism
        breaker = Breakers.dynamic(key, self, @maxretry, @findtime, @bantime)

        # Check if circuit is open (banned)
        if breaker.open?
          stats = breaker.stats
          # Integer nanoseconds, like findtime and bantime.
          banned_for = Breakers.since(breaker)
          time_until_unban = banned_for ? [@bantime - banned_for, 0].max : @bantime

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

        breaker = Breakers.dynamic(key, self, @maxretry, @findtime, @bantime)

        # Record failure by trying to call through the breaker
        # and letting it fail
        begin
          breaker.call { raise 'Fail2Ban failure' }
        rescue StandardError
          # Expected - this records the failure
        end
      end
    end
  end
end
