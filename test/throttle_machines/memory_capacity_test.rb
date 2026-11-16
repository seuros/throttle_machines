# frozen_string_literal: true

require 'test_helper'

module ThrottleMachines
  class MemoryCapacityTest < Test
    def setup
      super
      @clock = TestClock.new(NS)
      @stores = []
    end

    def teardown
      @stores.each(&:shutdown)
      @clock.reset
      super
    end

    GCRA = GcraPolicy.new(NS, 0)
    BUCKET = TokenBucketPolicy.new(1, NS)
    TTL = 60 * NS
    WINDOW = 60 * NS

    def test_algorithms_fail_closed_without_resetting_existing_keys
      assert_algorithm_caps
    end

    def test_budget_is_shared_by_all_stores
      storage = memory(3)
      assert_equal 1, storage.increment_counter('counter', WINDOW)
      assert storage.check_gcra('gcra', GCRA, TTL).is_a?(Integer)
      assert storage.check_token_bucket('bucket', BUCKET, TTL).is_a?(Integer)
      assert_equal Storage::Base::UNTRACKED, storage.increment_counter('unknown', WINDOW)
      assert_equal :full, storage.check_gcra('unknown', GCRA, TTL)
      assert_equal :full, storage.check_token_bucket('unknown', BUCKET, TTL)
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
      assert_equal 1, storage.increment_counter('old', WINDOW)
      100.times do |i|
        assert_equal Storage::Base::UNTRACKED, storage.increment_counter("spray-#{i}", WINDOW)
      end
      assert_equal 1, scans
      @clock.advance(60 * NS)
      assert_equal 1, storage.increment_counter('fresh', WINDOW)
      assert_equal 2, scans
      assert_equal 1, stored_keys(storage)
    end

    def test_reset_and_clear_release_capacity
      storage = memory(1)
      storage.increment_counter('counter', WINDOW)
      storage.reset_counter('counter', WINDOW)
      assert storage.check_gcra('gcra', GCRA, TTL).is_a?(Integer)
      storage.clear('gcra*')
      assert storage.check_token_bucket('bucket', BUCKET, TTL).is_a?(Integer)
      storage.clear
      assert_equal 1, storage.increment_counter('fresh', WINDOW)
      assert_equal 1, stored_keys(storage)
    end

    def test_cleanup_does_not_delete_a_concurrently_refreshed_entry
      storage = memory(1)
      assert storage.check_gcra('known', GCRA, NS).is_a?(Integer)
      @clock.advance(2 * NS)
      state = storage.instance_variable_get(:@state)
      write_lock = state.method(:with_write_lock)
      refreshed = false
      state.define_singleton_method(:with_write_lock) do |key, &block|
        write_lock.call(key) do
          unless refreshed
            refreshed = true
            # Simulate a writer refreshing the TTL after cleanup has selected
            # the key, but before cleanup acquires its striped lock.
            data = gcra_states.fetch(key)
            store_entry(gcra_states, key, data.merge(expires_at: ThrottleMachines.monotonic_time + (60 * NS)))
          end
          block.call
        end
      end
      storage.send(:clean_expired_entries)
      assert refreshed
      assert_equal 1, stored_keys(storage)
      assert_equal :full, storage.check_gcra('unknown', GCRA, TTL)
    end

    def test_existing_counter_can_still_increment_when_full
      storage = memory(1)
      assert_equal 1, storage.increment_counter('known', WINDOW)
      assert_equal 2, storage.increment_counter('known', WINDOW)
      assert_equal Storage::Base::UNTRACKED, storage.get_counter('unknown', WINDOW)
      assert_operator storage.get_counter_ttl('unknown', WINDOW), :>, 0
    end

    def test_limiter_throttles_unknown_identities_for_every_algorithm
      %i[fixed_window gcra token_bucket].each do |algorithm|
        storage = memory(1)
        known = Limiter.new('known', limit: 1, period: 60 * NS, algorithm: algorithm, storage: storage)
        unknown = Limiter.new('unknown', limit: 1, period: 60 * NS, algorithm: algorithm, storage: storage)
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
      assert_equal Storage::Base::UNTRACKED, storage.increment_counter('counter', WINDOW)
      refute storage.check_gcra('gcra', GCRA, TTL).is_a?(Integer)
      refute storage.check_token_bucket('bucket', BUCKET, TTL).is_a?(Integer)
      assert_equal 0, stored_keys(storage)
      [nil, false, 1.5, '10'].each do |value|
        assert_raises(TypeError) { Storage::Memory.new(max_keys: value) }
      end
      assert_raises(RangeError) { Storage::Memory.new(max_keys: -1) }
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
            when 0 then storage.increment_counter(key, WINDOW)
            when 1 then storage.check_gcra(key, GCRA, TTL)
            when 2 then storage.check_token_bucket(key, BUCKET, TTL)
            end
          end
        end
      end
      8.times { ready.pop }
      8.times { start << true }
      workers.each(&:value)
      assert_equal 7, stored_keys(storage)
      assert_equal 7, storage.instance_variable_get(:@state).stored_keys
    end

    private

    def memory(max_keys)
      Storage::Memory.new(max_keys: max_keys, auto_cleanup: false).tap { |store| @stores << store }
    end

    def stored_keys(storage)
      %i[@counters @gcra_states @token_buckets].sum { |name| storage.instance_variable_get(name).size }
    end

    def assert_algorithm_caps
      [
        %i[check_gcra peek_gcra gcra_retry_after GCRA],
        %i[check_token_bucket peek_token_bucket token_bucket_retry_after BUCKET]
      ].each do |check, peek, retry_after, policy_name|
        policy = self.class.const_get(policy_name)
        storage = memory(1)

        assert_equal 0, storage.public_send(check, 'known', policy, TTL)
        100.times do |i|
          assert_equal :full, storage.public_send(check, "spray-#{i}", policy, TTL)
          assert_operator storage.public_send(retry_after, "spray-#{i}", policy), :>, 0
        end

        assert_equal :full, storage.public_send(peek, 'unknown', policy)
        assert_equal :throttled, storage.public_send(check, 'known', policy, TTL), 'active state must not be evicted'
        assert_equal 1, stored_keys(storage)
        @clock.advance(NS)

        assert_equal 0, storage.public_send(check, 'known', policy, TTL), 'known keys can recover at capacity'
        @clock.advance(60 * NS)

        assert_equal 0, storage.public_send(check, 'fresh', policy, TTL), 'expired keys free slots'
        assert_equal 1, stored_keys(storage)
      end
    end
  end
end
