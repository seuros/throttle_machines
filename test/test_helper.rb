# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require 'minitest/autorun'
require 'active_support'
require 'active_support/test_case'

# `rake test TESTOPTS=--coverage` measures with padded_cell; this shapes the report.
if defined?(PaddedCell.coverage)
  PaddedCell.coverage do
    track 'lib/**/*.rb' # files the suite never loads report at 0%
  end
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'throttle_machines'

# Load test support files
require_relative 'support/test_clock'

module ThrottleMachines
  class Test < ActiveSupport::TestCase
    def setup
      ThrottleMachines.reset!
    end
  end
end
