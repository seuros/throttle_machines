# frozen_string_literal: true

require 'json'
require 'timeout'
require 'zeitwerk'
require 'active_support'
require 'active_support/core_ext/class/attribute'

# Ecosystem dependencies
require 'chrono_machines'
require 'deadline_machines'
require 'breaker_machines'

# Rate limiting over a native Rust core.
#
# Every instant and span in this gem is Integer nanoseconds: `now` as read
# from `Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)`, and
# every period, window, interval, TTL and retry_after. Arguments are in
# 0..2**64-1, except a native gate's instants (`now`, `tat`, `refilled_at`,
# `window_start`), which take the whole Duration range, so every instant a
# gate returns reads back.
#
# Every Data value below is held to what the core accepts, whether the gem
# built it or the caller did: TypeError for the wrong type, RangeError for a
# value outside the core's domain.
module ThrottleMachines
  # One call per `emission_interval`, with up to `delay_tolerance` of calls
  # ahead of schedule allowed as a burst. `emission_interval` is positive, and
  # the burst ceiling (`delay_tolerance + emission_interval`) holds at most
  # 2**64-1 intervals, so every count a gate answers is exact.
  # `GcraPolicy.per(period, limit, burst)` spreads `limit` calls over
  # `period`, `burst` of them back to back (1 for none), rounding the
  # interval up to the nanosecond so the rate never exceeds the one asked for.
  GcraPolicy = Data.define(:emission_interval, :delay_tolerance) do
    def self.per(period, limit, burst)
      new(*ThrottleMachines.__send__(:__gcra_per, period, limit, burst))
    end

    def initialize(emission_interval:, delay_tolerance:)
      ThrottleMachines.__send__(:__gcra_policy, emission_interval, delay_tolerance)
      super
    end
  end

  # A burst of `capacity` calls (positive), one token earned every
  # `refill_every` (positive). `TokenBucketPolicy.per(period, limit)` holds
  # `limit` tokens and spreads their refill over `period`, rounded up.
  TokenBucketPolicy = Data.define(:capacity, :refill_every) do
    def self.per(period, limit)
      new(*ThrottleMachines.__send__(:__token_bucket_per, period, limit))
    end

    def initialize(capacity:, refill_every:)
      ThrottleMachines.__send__(:__token_bucket_policy, capacity, refill_every)
      super
    end
  end

  # `limit` calls (positive) per `window` (positive).
  FixedWindowPolicy = Data.define(:window, :limit) do
    def initialize(window:, limit:)
      ThrottleMachines.__send__(:__fixed_window_policy, window, limit)
      super
    end
  end
end

# Native is required: no algorithm fallback. It validates the Data values
# above and defines the gates over them (Gcra, TokenBucket, FixedWindow),
# so they must exist first.
require 'throttle_machines_native/throttle_machines_native'

module ThrottleMachines
  private_class_method :__gcra_policy, :__token_bucket_policy, :__fixed_window_policy, :__gcra_per,
                       :__token_bucket_per

  # The values are sealed. `initialize` is where each validates, and a
  # subclass could override it, or `allocate` build an instance that never
  # ran it: subclassing raises TypeError and `allocate` is gone. Sealing stops
  # accidents, not reflection (`Marshal.load` skips `initialize`), so the
  # native side is the authority: a policy it reads must be exactly its
  # class, and its fields are checked again.
  [GcraPolicy, TokenBucketPolicy, FixedWindowPolicy].each do |value|
    value.singleton_class.undef_method(:allocate)
    value.define_singleton_method(:inherited) { |_| raise TypeError, "#{value} cannot be subclassed" }
  end
end

# The runtime layered on the gates: limiters over shared storage, Rack and
# Rails integration. Its keywords belong to it; the core has no counterpart.
loader = Zeitwerk::Loader.for_gem
# The engine is required below, not autoloaded: nothing references
# ThrottleMachines::Engine, and a Rails::Engine registers its initializers
# only when its class is defined.
loader.ignore("#{__dir__}/throttle_machines/engine.rb")
loader.ignore("#{__dir__}/throttle_machines/async_support.rb")
loader.ignore("#{__dir__}/throttle_machines_native")
loader.setup

module ThrottleMachines
  NS_PER_SECOND = 1_000_000_000

  class Configuration
    attr_accessor :default_storage, :default_algorithm, :instrumentation_enabled,
                  :instrumentation_backend, :_storage_instance
    attr_reader :fiber_safe

    def initialize
      @default_storage = :memory
      @default_algorithm = :fixed_window
      @instrumentation_enabled = true
      @instrumentation_backend = nil
      @fiber_safe = false
      @_storage_instance = nil
    end

    def fiber_safe=(value)
      @fiber_safe = !!value
      ThrottleMachines.load_async_runtime! if @fiber_safe
    end
  end

  @config = Configuration.new

  class << self
    attr_reader :config

    # The clock every limiter reads: Integer nanoseconds, monotonic.
    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    end

    def configure
      yield(config) if block_given?

      Instrumentation.enabled = config.instrumentation_enabled
      Instrumentation.backend = config.instrumentation_backend if config.instrumentation_backend
      load_async_runtime! if config.fiber_safe
    end

    def storage
      config._storage_instance ||= create_storage(config.default_storage)
    end

    def storage=(value)
      config._storage_instance = create_storage(value)
    end

    def reset!(key = nil)
      if key
        storage.reset_key(key)
      else
        storage.clear
        config._storage_instance = nil
        Instrumentation.enabled = config.instrumentation_enabled
        Instrumentation.backend = config.instrumentation_backend
      end
    end

    def control(key, &block)
      control = Control.new(key)
      control.instance_eval(&block) if block
      control
    end

    def limit(key, limit:, period:, algorithm: nil, &)
      limiter(key, limit: limit, period: period, algorithm: algorithm).throttle!(&)
    end

    # Runs the block through the registry's shared circuit `key`: it opens
    # on `failures` within `within` and stays open `timeout` (default
    # `within`), both Integer nanoseconds, like Control#break_on.
    def break_circuit(key, failures:, within:, timeout: within, &)
      Breakers.dynamic(key, self, failures, within, timeout).call(&)
    end

    # ChronoMachines.retry: a backoff shape (ChronoMachines::Exponential,
    # Constant or Fibonacci), the attempt cap, and the executor's keywords.
    def retry_with(strategy, max_attempts, **runtime, &)
      ChronoMachines.retry(strategy, max_attempts, **runtime, &)
    end

    def limiter(key, limit:, period:, algorithm: nil)
      Limiter.new(key, limit: limit, period: period, algorithm: algorithm || config.default_algorithm,
                       storage: storage)
    end

    def async_breaker(...)
      AsyncBreaker.new(...)
    end

    # Runs the block through a HedgedRequest built with these keywords, then
    # shuts its executor down.
    def hedged_request(**, &)
      hedged = HedgedRequest.new(**)
      begin
        hedged.run(&)
      ensure
        hedged.shutdown
      end
    end

    def load_async_runtime!
      require 'async'
      require 'async/task'
      true
    rescue LoadError => e
      raise unless e.message.include?('async')

      raise LoadError, "The 'async' gem is required for fiber_safe mode. Add `gem 'async'` to your Gemfile."
    end

    private

    def create_storage(storage)
      case storage
      when Symbol then create_storage_from_symbol(storage)
      when Class then storage.new
      when Storage::Base then storage
      else raise TypeError, "Invalid storage: #{storage.inspect}"
      end
    end

    def create_storage_from_symbol(symbol)
      case symbol
      when :memory then Storage::Memory.new
      when :cache then Storage::Cache.new
      when :null then Storage::Null.new
      when :redis
        raise ArgumentError, 'Redis storage requires a Redis client instance. ' \
                             'Configure with: ThrottleMachines.storage = Storage::Redis.new(redis: Redis.new)'
      else raise RangeError, "Unknown storage type: #{symbol}"
      end
    end
  end

  configure

  CircuitOpenError = BreakerMachines::CircuitOpenError
  RetryExhaustedError = ChronoMachines::MaxRetriesExceededError
end

require_relative 'throttle_machines/async_support'
require_relative 'throttle_machines/engine' if defined?(Rails::Engine)
