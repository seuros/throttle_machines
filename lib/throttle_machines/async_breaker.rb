# frozen_string_literal: true

module ThrottleMachines
  class AsyncBreaker
    class << self
      def new(...)
        ThrottleMachines.load_async_runtime!
        BreakerMachines::AsyncCircuit.new(...)
      end
    end
  end
end
