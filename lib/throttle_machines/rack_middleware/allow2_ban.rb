# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    class Allow2Ban
      attr_reader :name, :maxretry, :findtime, :bantime, :block

      def initialize(name, options, &block)
        @name = name
        @block = block

        @maxretry = options[:maxretry] || 5
        @findtime = options[:findtime] || 60
        @bantime = options[:bantime] || 300
      end

      def matched_by?(request)
        discriminator = discriminator_for(request)
        return false unless discriminator

        # Allow2Ban resets fail2ban counters on successful requests
        # We'll track successful requests and reset the breaker when threshold is met

        success_key = "allow2ban:#{@name}:#{discriminator}"
        fail_key = "fail2ban:#{@name}:#{discriminator}"

        # Count successful requests
        success_limiter = ThrottleMachines.limiter(
          success_key,
          limit: @maxretry,
          period: @findtime,
          algorithm: :fixed_window
        )

        # Check if we've had enough successful requests
        if success_limiter.remaining.zero?
          # Reset the fail2ban breaker (use BreakerMachines circuit)
          breaker = BreakerMachines::Registry.instance.get_or_create_dynamic_circuit(
            fail_key,
            self,
            failure_threshold: @maxretry,
            failure_window: @findtime,
            reset_timeout: @bantime
          )
          breaker.hard_reset

          # Reset our own counter
          ThrottleMachines.storage.reset_counter(success_key, @findtime)
        else
          # Increment success counter
          begin
            success_limiter.throttle!
          rescue ThrottledError
            # We've hit the limit, which triggers the reset above
          end
        end

        false # Allow2Ban never blocks directly
      end

      private

      def discriminator_for(request)
        @block.call(request)
      end
    end
  end
end
