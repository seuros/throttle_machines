# frozen_string_literal: true

module ThrottleMachines
  # Error raised when dependencies aren't satisfied
  class DependencyError < StandardError; end
end
