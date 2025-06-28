# frozen_string_literal: true

module ThrottleMachines
  class RackMiddleware
    # Rack 3 Request wrapper
    class Request < ::Rack::Request
      def user_agent
        @env['HTTP_USER_AGENT']
      end
    end
  end
end
