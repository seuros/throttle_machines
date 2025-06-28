# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class VersionTest < Test
    def test_that_it_has_a_version_number
      assert_not_nil ::ThrottleMachines::VERSION
    end
  end
end
