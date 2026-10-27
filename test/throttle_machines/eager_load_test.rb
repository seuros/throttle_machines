# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class EagerLoadTest < Test
    def test_every_managed_file_eager_loads
      Zeitwerk::Loader.eager_load_all

      assert defined?(ThrottleMachines::Limiter)
    end
  end
end
