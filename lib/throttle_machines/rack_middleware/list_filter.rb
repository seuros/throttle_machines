# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    # Base class for Safelist and Blocklist filters.
    #
    # Both match a request against a user-supplied block and, on a match, tag the
    # rack env and emit instrumentation. They differ only in the +match_type+
    # recorded on the env, which subclasses provide.
    class ListFilter
      attr_reader :name, :block

      def initialize(name, &block)
        @name = name
        @block = block
      end

      def matched_by?(request)
        return false unless @block

        if @block.call(request)
          request.env['rack.attack.matched'] = @name
          request.env['rack.attack.match_type'] = match_type
          ThrottleMachines::RackMiddleware.instrument(request)
          true
        else
          false
        end
      end

      private

      # @return [Symbol] the rack.attack match type recorded for this filter
      def match_type
        raise NotImplementedError, "#{self.class} must implement #match_type"
      end
    end
  end
end
