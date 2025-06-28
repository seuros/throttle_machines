# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_support/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'rails/test_unit/railtie'

# Require the gems listed in Gemfile, including throttle_machines
Bundler.require(*Rails.groups)

# Require the rack middleware
require 'throttle_machines/rack_middleware'

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    # Only load the frameworks we need
    config.api_only = true

    # Skip some Rails features we don't need
    config.generators.system_tests = nil

    # Configure ThrottleMachines defaults for testing
    config.after_initialize do
      ThrottleMachines.configure do |config|
        config.storage = ThrottleMachines::Storage::Memory.new
      end
    end

    # Add the middleware
    config.middleware.use ThrottleMachines::RackMiddleware
  end
end
