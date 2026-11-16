# frozen_string_literal: true

require 'test_helper'
require 'open3'

module ThrottleMachines
  # A Rails app that loads the gem gets the engine, and through it the
  # controller helpers. Booted in a child process: the suite itself loads the
  # gem without Rails, and an application can be initialized once per process.
  class EngineTest < Test
    APP = <<~RUBY
      require 'rails'
      require 'action_controller/railtie'
      require 'throttle_machines'

      class EngineProbe < Rails::Application
        config.eager_load = false
        config.logger = Logger.new(nil)
        config.secret_key_base = 'x' * 64
      end
      EngineProbe.initialize!

      puts ThrottleMachines::Engine < Rails::Engine
      puts ActionController::Base.include?(ThrottleMachines::ControllerHelpers)
      puts ActionController::API.include?(ThrottleMachines::ControllerHelpers)
    RUBY

    def test_a_rails_app_includes_the_controller_helpers
      lib = File.expand_path('../../lib', __dir__)
      out, err, status = Open3.capture3(RbConfig.ruby, '-I', lib, '-e', APP)

      assert_predicate status, :success?, err
      assert_equal %w[true true true], out.lines(chomp: true)
    end
  end
end
