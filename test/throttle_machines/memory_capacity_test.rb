# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class MemoryCapacityTest < Test
    def setup
      super
      @clock = TestClock.new(1.0)
      @stores = []
    end

    def teardown
      @stores.each(&:shutdown)
      @clock.reset
      super
    end

    def test_ruby_algorithms_fail_closed_without_resetting_existing_keys
      assert_algorithm_caps(native: false)
    end

    def test_native_algorithms_fail_closed_without_resetting_existing_keys
      skip 'native extension not loaded' unless defined?(Storage::NativeGCRA)

      assert_algorithm_caps(native: true)
    end

    def test_budget_is_shared_by_all_stores
      storage = memory(3)
      assert_equal 1, storage.increment_counter('counter', 60)
      assert storage.check_gcra_limit('gcra', 1.0, 0, 60)[:allowed]
      assert storage.check_token_bucket('bucket', 1, 1.0, 60)[:allowed]
      assert_equal Float::INFINITY, storage.increment_counter('unknown', 60)
      refute storage.check_gcra_limit('unknown', 1.0, 0, 60)[:allowed]
      refute storage.check_token_bucket('unknown', 1, 1.0, 60)[:allowed]
      assert_equal 3, stored_keys(storage)
    end

    def test_cleanup_is_throttled_and_expired_entries_release_capacity
      storage = memory(1)
      scans = 0
      cleanup = storage.method(:clean_expired_entries)
      storage.define_singleton_method(:clean_expired_entries) do
        scans += 1
        cleanup.call
      end
      assert_equal 1, storage.increment_counter('old', 60)
      100.times do |i|
        assert_equal Float::INFINITY, storage.increment_counter("spray-#{i}", 60)
      end
      assert_equal 1, scans
      @clock.advance(60)
      assert_equal 1, storage.increment_counter('fresh', 60)
      assert_equal 2, scans
      assert_equal 1, stored_keys(storage)
    end

    def test_reset_and_clear_release_capacity
      storage = memory(1)
      storage.increment_counter('counter', 60)
      storage.reset_counter('counter', 60)
      assert storage.check_gcra_limit('gcra', 1.0, 0, 60)[:allowed]
      storage.clear('gcra*')
      assert storage.check_token_bucket('bucket', 1, 1.0, 60)[:allowed]
      storage.clear
      assert_equal 1, storage.increment_counter('fresh', 60)
      assert_equal 1, stored_keys(storage)
    end

    def test_cleanup_does_not_delete_a_concurrently_refreshed_entry
      storage = memory(1)
      assert storage.check_gcra_limit('known', 1.0, 0, 1)[:allowed]
      @clock.advance(2)
      write_lock = storage.method(:with_write_lock)
      refreshed = false
      storage.define_singleton_method(:with_write_lock) do |key, &block|
        write_lock.call(key) do
          unless refreshed
            refreshed = true
            # Simulate a writer refreshing the TTL after cleanup has selected
            # the key, but before cleanup acquires its striped lock.
            data = @gcra_states.fetch(key)
            store_entry(@gcra_states, key, data.merge(expires_at: current_time + 60))
          end
          block.call
        end
      end
      storage.send(:clean_expired_entries)
      assert refreshed
      assert_equal 1, stored_keys(storage)
      refute storage.check_gcra_limit('unknown', 1.0, 0, 60)[:allowed]
    end

    def test_existing_counter_can_still_increment_when_full
      storage = memory(1)
      assert_equal 1, storage.increment_counter('known', 60)
      assert_equal 2, storage.increment_counter('known', 60)
      assert_equal Float::INFINITY, storage.get_counter('unknown', 60)
      assert_operator storage.get_counter_ttl('unknown', 60), :>, 0
    end

    def test_limiter_throttles_unknown_identities_for_every_algorithm
      %i[fixed_window gcra token_bucket].each do |algorithm|
        storage = memory(1)
        known = Limiter.new('known', limit: 1, period: 60, algorithm: algorithm, storage: storage)
        unknown = Limiter.new('unknown', limit: 1, period: 60, algorithm: algorithm, storage: storage)
        known.throttle!
        refute unknown.allow?, algorithm
        assert_equal 0, unknown.remaining, algorithm
        assert_raises(ThrottledError) { unknown.throttle! }
        assert_operator unknown.retry_after, :>, 0
        assert_equal 1, stored_keys(storage)
      end
    end

    def test_zero_budget_and_invalid_configuration
      storage = memory(0)
      assert_equal Float::INFINITY, storage.increment_counter('counter', 60)
      refute storage.check_gcra_limit('gcra', 1.0, 0, 60)[:allowed]
      refute storage.check_token_bucket('bucket', 1, 1.0, 60)[:allowed]
      assert_equal 0, stored_keys(storage)
      [-1, nil, false, 1.5, '10'].each do |value|
        assert_raises(ArgumentError) { Storage::Memory.new(max_keys: value) }
      end
    end

    def test_concurrent_mixed_admissions_cannot_overrun_budget
      storage = memory(7)
      ready = Queue.new
      start = Queue.new
      workers = 8.times.map do |worker|
        Thread.new do
          ready << true
          start.pop
          32.times do |i|
            key = "#{worker}-#{i}"
            case i % 3
            when 0 then storage.increment_counter(key, 60)
            when 1 then storage.check_gcra_limit(key, 1.0, 0, 60)
            when 2 then storage.check_token_bucket(key, 1, 1.0, 60)
            end
          end
        end
      end
      8.times { ready.pop }
      8.times { start << true }
      workers.each(&:value)
      assert_equal 7, stored_keys(storage)
      assert_equal 7, storage.instance_variable_get(:@stored_keys)
    end

    private

    def memory(max_keys)
      Storage::Memory.new(max_keys: max_keys, auto_cleanup: false).tap { |store| @stores << store }
    end

    def stored_keys(storage)
      %i[@counters @gcra_states @token_buckets].sum { |name| storage.instance_variable_get(name).size }
    end

    def call_algorithm(storage, native, name, *args)
      return storage.public_send(name, *args) if native

      method = Storage::Memory.instance_method(name)
      method = method.super_method until method.owner == Storage::Memory
      method.bind_call(storage, *args)
    end

    def assert_algorithm_caps(native:)
      [
        [:check_gcra_limit, :peek_gcra_limit, [1.0, 0, 60], [1.0, 0]],
        [:check_token_bucket, :peek_token_bucket, [1, 1.0, 60], [1, 1.0]]
      ].each do |check, peek, check_args, peek_args|
        storage = memory(1)
        call = ->(name, key, args) { call_algorithm(storage, native, name, key, *args) }
        assert call.(check, 'known', check_args)[:allowed]
        100.times do |i|
          refused = call.(check, "spray-#{i}", check_args)
          refute refused[:allowed]
          assert_operator refused[:retry_after], :>, 0
        end
        refute call.(peek, 'unknown', peek_args)[:allowed]
        refute call.(check, 'known', check_args)[:allowed], 'active state must not be evicted'
        assert_equal 1, stored_keys(storage)
        @clock.advance(1)
        assert call.(check, 'known', check_args)[:allowed], 'known keys can recover at capacity'
        @clock.advance(60)
        assert call.(check, 'fresh', check_args)[:allowed], 'expired keys free slots'
        assert_equal 1, stored_keys(storage)
      end
    end
  end
end
