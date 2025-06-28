# frozen_string_literal: true

require 'throttle_machines/controller_helpers'
require 'throttle_machines/middleware'

module ThrottleMachines
  class Engine < ::Rails::Engine
    isolate_namespace ThrottleMachines

    initializer 'throttle_machines.controller_helpers' do
      ActiveSupport.on_load(:action_controller) do
        include ThrottleMachines::ControllerHelpers
      end
    end

    initializer 'throttle_machines.configure_defaults' do |_app|
      ThrottleMachines.configure do |config|
        # Use Redis if available in Rails cache
        if defined?(Redis) && Rails.cache.respond_to?(:redis)
          config.store = ThrottleMachines::Stores::Redis.new(Rails.cache.redis)
        end
      end
    end
  end
end
