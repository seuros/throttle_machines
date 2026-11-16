# frozen_string_literal: true

module ThrottleMachines
  # The one seam between this gem and BreakerMachines circuits. Both speak
  # Integer nanoseconds; this module only shapes the core's Policy and reads
  # spans back off a circuit's own clock.
  module Breakers
    # The `exceptions:` a circuit guarding a limiter counts: any
    # StandardError but ThrottledError. Being throttled says nothing about
    # the guarded service, so it passes through uncounted.
    module Failure
      def self.===(error) = error.is_a?(StandardError) && !error.is_a?(ThrottledError)
    end

    module_function

    # The Policy every ThrottleMachines circuit runs: open on `failures`
    # within `window`, stay open exactly `cooldown` (no jitter), then close
    # on one successful probe. `window` and `cooldown` are Integer
    # nanoseconds.
    def policy(failures, window, cooldown)
      BreakerMachines::Policy.new(
        BreakerMachines::Threshold.new(failures, nil, 0),
        window,
        BreakerMachines::Recovery.new(cooldown, 0.0, 1, 1),
        nil
      )
    end

    # The registry's shared circuit `name`, created on first use with
    # `policy(failures, window, cooldown)` and owned by `owner`.
    def dynamic(name, owner, failures, window, cooldown, **runtime)
      BreakerMachines::Registry.instance.get_or_create_dynamic_circuit(
        name, owner, policy(failures, window, cooldown), **runtime
      )
    end

    # Integer nanoseconds since `circuit` opened, on the circuit's clock (a
    # wall clock when it shares state through a storage), or nil when it is
    # not open.
    def since(circuit)
      opened_at = circuit.stats.opened_at
      opened_at && (circuit.now - opened_at)
    end
  end
end
