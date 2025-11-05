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

    # No default Rails.cache binding; storage is managed by ThrottleMachines
  end
end
