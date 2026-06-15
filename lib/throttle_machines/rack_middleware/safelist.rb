# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    # Allows (short-circuits) requests matching the configured block.
    class Safelist < ListFilter
      private

      def match_type
        :safelist
      end
    end
  end
end
