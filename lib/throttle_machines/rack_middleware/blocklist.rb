# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    # Blocks requests matching the configured block (returns true => blocked).
    class Blocklist < ListFilter
      private

      def match_type
        :blocklist
      end
    end
  end
end
