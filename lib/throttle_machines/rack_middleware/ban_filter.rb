# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    # Base class for Fail2Ban and Allow2Ban filters.
    #
    # Both are configured with the same maxretry/findtime/bantime thresholds and
    # derive a discriminator from the request via the supplied block. The ban
    # logic itself lives in each subclass.
    class BanFilter
      attr_reader :name, :maxretry, :findtime, :bantime, :block

      def initialize(name, options, &block)
        @name = name
        @block = block

        @maxretry = options[:maxretry] || 5
        @findtime = options[:findtime] || 60
        @bantime = options[:bantime] || 300
      end

      private

      def discriminator_for(request)
        @block.call(request)
      end
    end
  end
end
