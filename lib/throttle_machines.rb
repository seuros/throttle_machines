# frozen_string_literal: true

require 'json'
require 'timeout'
require 'zeitwerk'
require 'active_support/configurable'

# Ecosystem dependencies
require 'chrono_machines'
require 'breaker_machines'

# Set up Zeitwerk loader
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/throttle_machines/engine.rb") unless defined?(Rails::Engine)
loader.setup

# Load conditional dependencies manually
require_relative 'throttle_machines/storage/redis' if defined?(Redis)

module ThrottleMachines
  include ActiveSupport::Configurable

  # Define configuration options with defaults
  config_accessor :default_limit, default: 100
  config_accessor :default_period, default: 60 # 1 minute
  config_accessor :default_storage, default: :memory
  config_accessor :clock, default: nil
  config_accessor :instrumentation_enabled, default: true
  config_accessor :instrumentation_backend
  config_accessor :_storage_instance

  class << self
    # Delegate monotonic time to BreakerMachines for consistency
    delegate :monotonic_time, to: :BreakerMachines

    def configure
      yield(config) if block_given?

      # Apply instrumentation settings
      Instrumentation.enabled = config.instrumentation_enabled
      Instrumentation.backend = config.instrumentation_backend if config.instrumentation_backend
    end

    def storage
      config._storage_instance ||= create_storage(config.default_storage)
    end

    def storage=(value)
      config._storage_instance = create_storage(value)
    end

    def reset!(key = nil)
      if key
        storage.clear("#{key}*")
      else
        storage.clear
        # Reset storage instance to force recreation with defaults
        config._storage_instance = nil
        # Re-apply instrumentation settings from the configuration
        Instrumentation.enabled = config.instrumentation_enabled
        Instrumentation.backend = config.instrumentation_backend
      end
    end

    def control(key, &block)
      control = Control.new(key)
      control.instance_eval(&block) if block
      control
    end

    def limit(key, limit:, period:, algorithm: :fixed_window, &)
      limiter = limiter(key, limit: limit, period: period, algorithm: algorithm)
      limiter.throttle!(&)
    end

    def break_circuit(key, failures:, timeout:, &)
      # Delegate to breaker_machines
      breaker = BreakerMachines::Circuit.new(
        key: key,
        failure_threshold: failures,
        timeout: timeout
      )
      breaker.call(&)
    end

    def retry_with(max_attempts: 3, backoff: :exponential, &)
      # Delegate to chrono_machines
      policy_options = {
        max_attempts: max_attempts,
        jitter_factor: backoff == :exponential ? 1.0 : 0.0
      }
      ChronoMachines.retry(policy_options, &)
    end

    def limiter(key, limit:, period:, algorithm: :fixed_window)
      Limiter.new(key, limit: limit, period: period, algorithm: algorithm, storage: storage)
    end

    private

    def create_storage(storage)
      case storage
      when Symbol
        create_storage_from_symbol(storage)
      when Class
        storage.new
      when Storage::Base
        storage
      else
        raise ArgumentError, "Invalid storage: #{storage.inspect}"
      end
    end

    def create_storage_from_symbol(symbol)
      case symbol
      when :memory
        Storage::Memory.new
      when :redis
        raise ArgumentError, 'Redis storage requires redis gem' unless defined?(Redis)

        raise ArgumentError, 'Redis storage requires a Redis client instance. ' \
                             'Configure with: config.storage = Storage::Redis.new(redis: Redis.new)'

      when :null
        Storage::Null.new
      else
        raise ArgumentError, "Unknown storage type: #{symbol}"
      end
    end
  end

  # Auto-configure with defaults
  configure

  # Backward compatibility aliases for error classes (defined after module setup)
  CircuitOpenError = BreakerMachines::CircuitOpenError if defined?(BreakerMachines::CircuitOpenError)
  RetryExhaustedError = ChronoMachines::MaxRetriesExceededError if defined?(ChronoMachines::MaxRetriesExceededError)
end
