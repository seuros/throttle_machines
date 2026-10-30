# frozen_string_literal: true

require 'test_helper'
require 'active_support/cache'

module ThrottleMachines
  class CacheStorageTest < Test
    class StoreWithoutDeleteMatched < ActiveSupport::Cache::MemoryStore
      def delete_matched(_matcher, _options = nil)
        raise NotImplementedError, "#{self.class.name} does not support delete_matched"
      end
    end

    class RedisLikeStore < ActiveSupport::Cache::MemoryStore
      attr_reader :matchers

      def redis = nil

      def delete_matched(matcher, _options = nil)
        (@matchers ||= []) << matcher
      end
    end

    WINDOW_START = 1_699_999_980

    def setup
      super
      @cache = ActiveSupport::Cache::MemoryStore.new
      @storage = Storage::Cache.new(cache_store: @cache)
      travel_to Time.at(WINDOW_START)
    end

    def test_counts_within_a_window
      3.times { @storage.increment_counter('api', 60) }

      assert_equal 3, @storage.get_counter('api', 60)
      assert_equal 5, @storage.increment_counter('api', 60, 2)
    end

    def test_windows_align_to_the_epoch
      travel_to Time.at(WINDOW_START + 40)
      @storage.increment_counter('api', 60)

      assert_in_delta 20.0, @storage.get_counter_ttl('api', 60), 0.001

      travel 20.seconds

      assert_equal 0, @storage.get_counter('api', 60)
      assert_equal 1, @storage.increment_counter('api', 60)
    end

    def test_counts_concurrent_increments_from_separate_instances
      threads = Array.new(8) do
        Thread.new do
          storage = Storage::Cache.new(cache_store: @cache)
          100.times { storage.increment_counter('api', 60) }
        end
      end
      threads.each(&:join)

      assert_equal 800, @storage.get_counter('api', 60)
    end

    def test_reset_counter_clears_the_current_window
      @storage.increment_counter('api', 60)
      @storage.reset_counter('api', 60)

      assert_equal 0, @storage.get_counter('api', 60)
    end

    def test_rejects_non_positive_windows
      assert_raises(ArgumentError) { @storage.increment_counter('api', 0) }
      assert_raises(ArgumentError) { @storage.get_counter_ttl('api', -1) }
    end

    def test_limiter_throttles_through_the_cache
      limiter = Limiter.new('api', limit: 2, period: 60, storage: @storage)
      2.times { limiter.throttle! }

      error = assert_raises(ThrottledError) { limiter.throttle! }
      assert_operator error.retry_after, :>, 0
      assert_equal 0, limiter.remaining
    end

    def test_supports_fixed_window_only
      assert @storage.supports?(:fixed_window)
      refute @storage.supports?(:gcra)
      refute @storage.supports?(:token_bucket)

      %i[gcra token_bucket].each do |algorithm|
        error = assert_raises(ArgumentError) do
          Limiter.new('api', limit: 1, period: 60, algorithm: algorithm, storage: @storage)
        end
        assert_match(/does not support/, error.message)
      end
    end

    def test_fails_open_when_the_store_does_not_count
      storage = Storage::Cache.new(cache_store: ActiveSupport::Cache::NullStore.new)
      limiter = Limiter.new('api', limit: 1, period: 60, storage: storage)

      3.times { assert_nil limiter.throttle! }
    end

    def test_fails_closed_when_configured
      storage = Storage::Cache.new(cache_store: ActiveSupport::Cache::NullStore.new, fail_closed: true)
      limiter = Limiter.new('api', limit: 1, period: 60, storage: storage)

      assert_raises(ThrottledError) { limiter.throttle! }
    end

    def test_clear_deletes_only_matching_counters
      namespaced = ActiveSupport::Cache::MemoryStore.new(namespace: 'app')
      storage = Storage::Cache.new(cache_store: namespaced)
      namespaced.write('unrelated', 'kept')
      storage.increment_counter('login:1.2.3.4', 60)
      storage.increment_counter('login:5.6.7.8', 60)

      storage.clear('login:1.2.3.4*')

      assert_equal 0, storage.get_counter('login:1.2.3.4', 60)
      assert_equal 1, storage.get_counter('login:5.6.7.8', 60)

      storage.clear

      assert_equal 0, storage.get_counter('login:5.6.7.8', 60)
      assert_equal 'kept', namespaced.read('unrelated')
    end

    def test_clear_passes_an_escaped_glob_to_redis
      store = RedisLikeStore.new
      Storage::Cache.new(cache_store: store).clear('ip:[::1]?*')

      assert_equal ['throttle_machines:ip:\[::1\]\?*'], store.matchers
    end

    def test_clear_raises_a_standard_error_when_the_store_cannot_match
      storage = Storage::Cache.new(cache_store: StoreWithoutDeleteMatched.new)

      error = assert_raises(UnsupportedOperationError) { storage.clear }
      assert_kind_of StandardError, error
    end

    def test_health_follows_the_store
      assert_predicate @storage, :healthy?
      refute_predicate Storage::Cache.new(cache_store: ActiveSupport::Cache::NullStore.new), :healthy?
    end

    def test_requires_a_cache_store_outside_rails
      skip 'Rails is loaded' if defined?(Rails)

      assert_raises(ArgumentError) { Storage::Cache.new }
    end
  end
end
