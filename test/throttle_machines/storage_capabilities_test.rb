# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class StorageCapabilitiesTest < Test
    class FixedWindowOnly < Storage::Base
      def initialize(options = {})
        super
        @counts = Hash.new(0)
      end

      def increment_counter(key, _window, amount = 1) = @counts[key] += amount
      def get_counter(key, _window) = @counts[key]
      def get_counter_ttl(_key, window) = window
      def reset_counter(key, _window) = @counts.delete(key)
    end

    class BrokenStore < FixedWindowOnly
      def get_counter(_key, _window) = raise(IOError, 'connection refused')
    end

    def test_detects_implemented_algorithms
      storage = FixedWindowOnly.new

      assert storage.supports?(:fixed_window)
      refute storage.supports?(:gcra)
      refute storage.supports?(:token_bucket)
      refute storage.supports?(:sliding_log)
    end

    def test_bundled_backends_support_every_algorithm
      [Storage::Memory.new(auto_cleanup: false), Storage::Null.new].each do |storage|
        %i[fixed_window gcra token_bucket].each do |algorithm|
          assert storage.supports?(algorithm), "#{storage.class} #{algorithm}"
        end
      end
    end

    def test_limiter_rejects_unsupported_algorithms_on_construction
      storage = FixedWindowOnly.new

      Limiter.new('api', limit: 1, period: 60, storage: storage).throttle!
      error = assert_raises(ArgumentError) do
        Limiter.new('api', limit: 1, period: 60, algorithm: :gcra, storage: storage)
      end
      assert_match(/FixedWindowOnly does not support the :gcra algorithm/, error.message)
    end

    def test_limiter_rejects_unknown_algorithms_on_construction
      assert_raises(ArgumentError) { Limiter.new('api', limit: 1, period: 60, algorithm: :sliding_log) }
    end

    def test_health_probe_needs_only_fixed_window
      assert_predicate FixedWindowOnly.new, :healthy?
      refute_predicate BrokenStore.new, :healthy?
    end

    def test_unimplemented_operations_name_the_backend
      error = assert_raises(NotImplementedError) { FixedWindowOnly.new.check_gcra_limit('api', 1.0, 0, 60) }
      assert_match(/FixedWindowOnly does not implement #check_gcra_limit/, error.message)
    end
  end
end
