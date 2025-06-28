# frozen_string_literal: true

require 'rack'
require 'forwardable'

module ThrottleMachines
  # Advanced Rack middleware for rate limiting and request filtering
  class RackMiddleware
    class << self
      extend Forwardable

      attr_accessor :enabled, :notifier
      attr_reader :configuration

      def_delegators :@configuration,
                     :throttle,
                     :track,
                     :safelist,
                     :blocklist,
                     :blocklist_ip,
                     :safelist_ip,
                     :fail2ban,
                     :allow2ban,
                     :throttled_responder,
                     :throttled_responder=,
                     :blocklisted_responder,
                     :blocklisted_responder=,
                     :throttles,
                     :tracks,
                     :safelists,
                     :blocklists

      def configure(&)
        @configuration ||= Configuration.new
        @configuration.instance_eval(&) if block
      end

      def reset!
        ThrottleMachines.reset!
      end

      def clear!
        @configuration = Configuration.new
      end

      # Instrument for ActiveSupport::Notifications compatibility
      def instrument(request)
        return unless notifier

        event_type = request.env['rack.attack.match_type']
        notifier.instrument("#{event_type}.throttle_machines", request: request)
      end
    end

    # Set defaults
    @enabled = true
    @notifier = ActiveSupport::Notifications if defined?(ActiveSupport::Notifications)
    @configuration = Configuration.new

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) if !self.class.enabled || env['rack.attack.called']

      env['rack.attack.called'] = true
      request = Request.new(env)

      # Always use the current class-level configuration
      configuration = self.class.configuration

      if configuration.safelisted?(request)
        @app.call(env)
      elsif configuration.blocklisted?(request)
        configuration.blocklisted_responder.call(request)
      elsif configuration.throttled?(request)
        configuration.throttled_responder.call(request)
      else
        configuration.tracked?(request)
        @app.call(env)
      end
    end
  end
end

# No alias - users should use the explicit name to avoid confusion
