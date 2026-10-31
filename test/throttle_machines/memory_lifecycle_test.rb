# frozen_string_literal: true

require 'test_helper'
require 'weakref'

module ThrottleMachines
  class MemoryLifecycleTest < Test
    GC_PASSES = 10
    ALLOCATIONS_PER_PASS = 10_000
    SETTLE_TIMEOUT = 5.0
    POLL_INTERVAL = 0.01
    SWEEP_INTERVAL = 0.01
    DROPPED_STORES = 20

    def test_an_explicitly_shut_down_store_is_collectible_and_stops_its_worker
      workers = threads_started { @ref = shut_down_store }
      collect_garbage

      refute @ref.weakref_alive?
      assert_empty alive(workers)
    end

    def test_a_dropped_store_is_collectible_and_its_worker_dies
      refs = nil
      workers = threads_started { refs = DROPPED_STORES.times.map { dropped_store } }

      assert_equal DROPPED_STORES, workers.size

      collect_garbage

      assert_equal 0, refs.count(&:weakref_alive?)
      assert_empty alive(workers)
    end

    def test_disabling_auto_cleanup_starts_no_worker
      store = Storage::Memory.new(auto_cleanup: false)

      assert_empty threads_started { store.shutdown }
    end

    def test_the_worker_keeps_sweeping_expired_entries_on_its_interval
      store = Storage::Memory.new(cleanup_interval: SWEEP_INTERVAL)
      counters = store.instance_variable_get(:@counters)
      store.increment_counter('swept', SWEEP_INTERVAL)

      refute_empty counters
      wait_until { counters.empty? }

      assert_empty counters
      store.shutdown
    end

    private

    def threads_started
      before = Thread.list
      yield
      Thread.list - before
    end

    def alive(workers)
      wait_until { workers.none?(&:alive?) }
      workers.select(&:alive?)
    end

    def wait_until
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SETTLE_TIMEOUT
      sleep POLL_INTERVAL until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end

    def collect_garbage
      GC_PASSES.times do
        ALLOCATIONS_PER_PASS.times { Object.new }
        GC.start
      end
    end

    def shut_down_store
      store = Storage::Memory.new
      store.shutdown
      WeakRef.new(store)
    end

    def dropped_store
      WeakRef.new(Storage::Memory.new)
    end
  end
end
