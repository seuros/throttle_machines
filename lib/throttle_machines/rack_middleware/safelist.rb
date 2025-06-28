# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    class Safelist
      attr_reader :name, :block

      def initialize(name, &block)
        @name = name
        @block = block
      end

      def matched_by?(request)
        return false unless @block

        if @block.call(request)
          request.env['rack.attack.matched'] = @name
          request.env['rack.attack.match_type'] = :safelist
          ThrottleMachines::RackMiddleware.instrument(request)
          true
        else
          false
        end
      end
    end
  end
end
