# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'throttle_machines'

require 'minitest/autorun'
require 'active_support'
require 'active_support/test_case'

# Load test support files
require_relative 'support/test_clock'

module ThrottleMachines
  class Test < ActiveSupport::TestCase
    def setup
      ThrottleMachines.reset!
    end
  end
end
