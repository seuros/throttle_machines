# frozen_string_literal: true

module ThrottleMachines
  # `AsyncBreaker.new(name, policy, **runtime)` builds a
  # BreakerMachines::AsyncCircuit (fiber-safe by default; `call_async`,
  # `fire_async`, `health_check_async`) once the `async` gem loads. Shape the
  # policy with Breakers.policy(failures, window, cooldown), spans in Integer
  # nanoseconds.
  class AsyncBreaker
    class << self
      def new(...)
        ThrottleMachines.load_async_runtime!
        BreakerMachines::AsyncCircuit.new(...)
      end
    end
  end
end
