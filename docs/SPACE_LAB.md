# 🔬 Space Lab

> **Testing in Zero Gravity** - Because in space, nobody can hear your tests fail

Welcome to the ThrottleMachines testing laboratory! Here we'll learn how to test your rate limiters, circuit breakers, and defensive systems without actually launching into the void.

Every limiter reads one clock: `ThrottleMachines.monotonic_time`, Integer
nanoseconds. Stub it and time stands still; advance it and periods elapse
exactly, no `sleep` required. Circuit breakers keep their own clock: pass any
callable answering Integer nanoseconds as `clock:`.

---

## 🧪 Basic Test Equipment

### Setting Up Your Lab
```ruby
# test/test_helper.rb or spec/spec_helper.rb
require 'throttle_machines'
require 'minitest/autorun'  # or 'rspec'

NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000

class ThrottleTest < Minitest::Test
  def setup
    # Reset the universe before each test
    ThrottleMachines.reset!
    BreakerMachines.registry.clear # shared circuits (break_circuit, fail2ban)

    # Use memory storage for speed (no sweeper thread in tests)
    ThrottleMachines.storage = ThrottleMachines::Storage::Memory.new(auto_cleanup: false)

    # Freeze time for predictable tests
    @time_machine = TimeMachine.new
  end

  def teardown
    @time_machine.return_to_present
  end

  # Consume one call: true when admitted, false when throttled.
  # (`allow?` only peeks; it never consumes.)
  def fire(limiter)
    limiter.throttle!
    true
  rescue ThrottleMachines::ThrottledError
    false
  end
end
```

---

## 🚀 Testing Rate Limiters

### Basic Limiter Testing
```ruby
class PhotonTorpedoTest < ThrottleTest
  def test_basic_rate_limiting
    # Create a torpedo launcher with 3 shots
    launcher = ThrottleMachines.limiter("torpedoes", limit: 3, period: 10 * NS)

    # Fire all torpedoes
    3.times do |i|
      assert fire(launcher), "Shot #{i+1} should be allowed"
    end

    # Fourth shot should fail
    refute fire(launcher), "Fourth shot should be blocked"

    # Check retry timing: time is frozen, so it is exact
    assert_equal 10 * NS, launcher.retry_after
  end

  def test_rate_limit_reset
    launcher = ThrottleMachines.limiter("torpedoes", limit: 2, period: 5 * NS)

    # Use up all shots
    2.times { fire(launcher) }
    refute launcher.allow?

    # Travel through time
    @time_machine.advance(5 * NS)

    # Torpedoes recharged!
    assert launcher.allow?, "Should reset after period"
  end
end
```

### Testing Different Algorithms
```ruby
class AlgorithmComparisonTest < ThrottleTest
  def test_fixed_window_hard_reset
    limiter = ThrottleMachines.limiter("fixed_test",
      limit: 100,
      period: 60 * NS,
      algorithm: :fixed_window
    )

    # Use 99 requests
    99.times { fire(limiter) }
    assert fire(limiter)  # 100th request
    refute fire(limiter)  # 101st blocked

    # Jump to just before window end
    @time_machine.advance(59 * NS)
    refute fire(limiter)  # Still blocked

    # Window resets exactly at boundary (60 s after its first request)
    @time_machine.advance(1 * NS)
    assert fire(limiter)  # Fresh window!
  end

  def test_token_bucket_regeneration
    bucket = ThrottleMachines.limiter("token_test",
      limit: 10,          # 10 tokens max
      period: 10 * NS,    # Refill in 10 seconds (one token per second)
      algorithm: :token_bucket
    )

    # Empty the bucket
    10.times { fire(bucket) }
    refute fire(bucket)

    # Wait for partial refill
    @time_machine.advance(5 * NS)

    # Exactly 5 tokens now
    5.times do |i|
      assert fire(bucket), "Token #{i+1} should be available"
    end
    refute fire(bucket), "Bucket should be empty again"
  end

  def test_gcra_smooth_distribution
    gcra = ThrottleMachines.limiter("gcra_test",
      limit: 60,
      period: 60 * NS,
      algorithm: :gcra
    )

    # GCRA prevents bursts and distributes evenly
    # Each request is spaced exactly 1 second apart

    assert fire(gcra)  # First is free

    # Second request immediately should fail
    refute fire(gcra), "GCRA prevents immediate burst"
    assert_equal 1 * NS, gcra.retry_after

    # But after 1 second, should allow
    @time_machine.advance(1 * NS)
    assert fire(gcra)
  end
end
```

---

## 🛡️ Testing Circuit Breakers

Circuits are `BreakerMachines::Circuit`s. They don't read
`ThrottleMachines.monotonic_time`; hand them the time machine as `clock:`.

### Basic Shield Testing
```ruby
class ShieldSystemTest < ThrottleTest
  def setup
    super
    # Open on 3 failures within 60 s, stay open 10 s, one good probe closes
    @shields = BreakerMachines::Circuit.new("test_shields",
      ThrottleMachines::Breakers.policy(3, 60 * NS, 10 * NS),
      clock: -> { @time_machine.now }
    )
  end

  def test_shield_activation
    # Normal operation
    assert_equal "Success", @shields.call { "Success" }

    # Simulate 3 failures
    3.times do |i|
      assert_raises(RuntimeError) do
        @shields.call { raise "System failure #{i+1}" }
      end
    end

    # Shields should now be UP
    assert @shields.open?
    assert_raises(ThrottleMachines::CircuitOpenError) do
      @shields.call { "This won't execute" }
    end
  end

  def test_shield_recovery
    # Trigger shield activation
    3.times do
      @shields.call { raise "Failure" } rescue nil
    end

    # Shields are up, for exactly the cooldown
    assert_raises(ThrottleMachines::CircuitOpenError) do
      @shields.call { "Blocked" }
    end
    assert_equal 10 * NS, @shields.retry_after

    # Wait for cooldown
    @time_machine.advance(10 * NS)

    # Shields attempt recovery (half-open probe)
    assert_equal "Success", @shields.call { "Success" }

    # Shields fully lowered after success
    assert @shields.closed?
    assert_equal "Normal operation", @shields.call { "Normal operation" }
  end

  def test_shield_reactivation
    # Activate shields
    3.times { @shields.call { raise "Error" } rescue nil }

    # Wait for recovery
    @time_machine.advance(10 * NS)

    # The half-open probe fails...
    assert_raises(RuntimeError) do
      @shields.call { raise "Another failure!" }
    end

    # Shields immediately go back up (half-open -> open)
    assert @shields.open?
    assert_raises(ThrottleMachines::CircuitOpenError) do
      @shields.call { "Blocked again" }
    end
  end
end
```

### Advanced Shield Patterns
```ruby
# Falls back to the secondary shield while the primary is up
CascadingDefense = Data.define(:primary, :secondary) do
  def execute(&block)
    primary.call(&block)
  rescue ThrottleMachines::CircuitOpenError
    secondary.call(&block)
  end
end

class AdvancedShieldTest < ThrottleTest
  def test_cascading_shields
    clock = -> { @time_machine.now }
    primary = BreakerMachines::Circuit.new("primary",
      ThrottleMachines::Breakers.policy(5, 60 * NS, 10 * NS), clock: clock)
    secondary = BreakerMachines::Circuit.new("secondary",
      ThrottleMachines::Breakers.policy(3, 60 * NS, 20 * NS), clock: clock)

    defense_system = CascadingDefense.new(primary, secondary)

    # Primary handles initial failures
    4.times do
      defense_system.execute { raise "Error" } rescue nil
    end

    # Primary still operational
    assert_equal "Primary success",
      defense_system.execute { "Primary success" }

    # Trigger primary shield
    2.times do
      defense_system.execute { raise "Error" } rescue nil
    end

    # Now using secondary
    assert_equal "Secondary success",
      defense_system.execute { "Secondary success" }
  end
end
```

---

## 🌐 Integration Testing

### Testing Rails Controllers
```ruby
# test/controllers/api_controller_test.rb
class ApiControllerTest < ActionDispatch::IntegrationTest
  setup do
    ThrottleMachines.reset!
  end

  test "throttles requests per user" do
    user = users(:captain_kirk)

    # Make requests up to limit
    10.times do |i|
      get api_status_path, headers: auth_headers(user)
      assert_response :success, "Request #{i+1} should succeed"
    end

    # 11th request should be throttled
    get api_status_path, headers: auth_headers(user)
    assert_response 429  # Too Many Requests

    # Check retry header
    assert response.headers["Retry-After"].to_i > 0
  end

  test "different users have separate limits" do
    kirk = users(:captain_kirk)
    spock = users(:commander_spock)

    # Max out Kirk's limit
    10.times do
      get api_status_path, headers: auth_headers(kirk)
    end

    # Kirk is throttled
    get api_status_path, headers: auth_headers(kirk)
    assert_response 429

    # But Spock can still make requests
    get api_status_path, headers: auth_headers(spock)
    assert_response :success
  end

  test "unauthenticated requests tracked by IP" do
    # Simulate requests from same IP
    10.times do
      get api_status_path, env: { "REMOTE_ADDR" => "192.168.1.100" }
      assert_response :success
    end

    # Should be throttled
    get api_status_path, env: { "REMOTE_ADDR" => "192.168.1.100" }
    assert_response 429

    # Different IP not affected
    get api_status_path, env: { "REMOTE_ADDR" => "192.168.1.200" }
    assert_response :success
  end
end
```

### Testing Rack Middleware
```ruby
class RackMiddlewareTest < Minitest::Test
  include Rack::Test::Methods

  def app
    # Build test app with middleware
    Rack::Builder.new do
      use ThrottleMachines::RackMiddleware

      run lambda { |env|
        [200, {"content-type" => "text/plain"}, ["Hello Space"]]
      }
    end
  end

  def setup
    ThrottleMachines.reset!
    ThrottleMachines::RackMiddleware.clear!  # drop rules from earlier tests

    # Configure middleware for testing
    ThrottleMachines::RackMiddleware.configure do |config|
      config.throttle("test_limit", limit: 3, period: 60 * NS) do |req|
        req.ip
      end

      config.blocklist_ip("192.168.1.666")
    end
  end

  def test_middleware_throttling
    # First 3 requests pass
    3.times do |i|
      get "/"
      assert_equal 200, last_response.status, "Request #{i+1}"
    end

    # 4th request throttled
    get "/"
    assert_equal 429, last_response.status
    assert_equal "60", last_response.headers["retry-after"]  # whole seconds, rounded up
  end

  def test_blocklist
    # Normal IP works
    get "/", {}, {"REMOTE_ADDR" => "192.168.1.1"}
    assert_equal 200, last_response.status

    # Blocked IP rejected
    get "/", {}, {"REMOTE_ADDR" => "192.168.1.666"}
    assert_equal 403, last_response.status
  end
end
```

---

## 🧬 Testing Utilities

### Time Travel Helper
```ruby
# Stands in for ThrottleMachines.monotonic_time: Integer nanoseconds that move
# only when a test moves them. (The gem's own suite does the same in
# test/support/test_clock.rb.)
class TimeMachine
  attr_reader :now

  def initialize(start = 1_000 * ThrottleMachines::NS_PER_SECOND)
    @now = start
    @original = ThrottleMachines.method(:monotonic_time)
    machine = self
    ThrottleMachines.singleton_class.define_method(:monotonic_time) { machine.now }
  end

  def advance(nanoseconds)
    @now += nanoseconds
  end

  def travel_to(nanoseconds)
    @now = nanoseconds
  end

  def return_to_present
    ThrottleMachines.singleton_class.define_method(:monotonic_time, @original)
  end
end
```

Memory and Redis storage read this clock. `Storage::Cache` aligns its windows
to the wall clock (`Time.now`), so the time machine does not move it.

### Custom Assertions
```ruby
module ThrottleAssertions
  # Peeks only: these never consume a call
  def assert_throttled(limiter, message = nil)
    refute limiter.allow?, message || "Expected to be throttled"
  end

  def assert_not_throttled(limiter, message = nil)
    assert limiter.allow?, message || "Expected not to be throttled"
  end

  # min and max are Integer nanoseconds
  def assert_retry_after_between(limiter, min, max, message = nil)
    retry_after = limiter.retry_after
    assert retry_after.between?(min, max),
      message || "Expected retry_after between #{min} and #{max} ns, got #{retry_after} ns"
  end

  def assert_circuit_open(breaker, message = nil)
    assert_equal :open, breaker.state,
      message || "Expected circuit to be open"
  end

  def assert_circuit_closed(breaker, message = nil)
    assert_equal :closed, breaker.state,
      message || "Expected circuit to be closed"
  end
end

# Include in your test classes
class MyTest < Minitest::Test
  include ThrottleAssertions
end
```

---

## 🔬 Performance Testing

### Benchmarking Different Algorithms
```ruby
class PerformanceLab < ThrottleTest
  def setup
    super
    @time_machine.return_to_present  # benchmarks need the real clock
  end

  def test_algorithm_performance
    iterations = 10_000

    algorithms = {
      fixed_window: :fixed_window,
      token_bucket: :token_bucket,
      gcra: :gcra
    }

    results = {}

    algorithms.each do |name, algorithm|
      limiter = ThrottleMachines.limiter("perf_#{name}",
        limit: 1000,
        period: 60 * NS,
        algorithm: algorithm
      )

      # Warm up
      100.times { limiter.allow? }

      # Benchmark, in Integer nanoseconds
      started = ThrottleMachines.monotonic_time
      iterations.times { limiter.allow? }
      elapsed = ThrottleMachines.monotonic_time - started

      results[name] = {
        total_time_ns: elapsed,
        ops_per_second: iterations * NS / elapsed,
        time_per_op_ns: elapsed / iterations
      }
    end

    # Print results
    puts "\nAlgorithm Performance Comparison:"
    puts "-" * 50
    results.each do |name, metrics|
      puts "#{name}:"
      puts "  Ops/second: #{metrics[:ops_per_second]}"
      puts "  Time/op: #{metrics[:time_per_op_ns]}ns"
    end

    # Assert reasonable performance
    results.each do |name, metrics|
      assert metrics[:ops_per_second] > 10_000,
        "#{name} too slow: #{metrics[:ops_per_second]} ops/sec"
    end
  end
end
```

### Load Testing
```ruby
class LoadTest < ThrottleTest
  def test_concurrent_access
    # Frozen clock: no time passes, so exactly one GCRA slot exists
    limiter = ThrottleMachines.limiter("concurrent_test",
      limit: 1000,
      period: 1 * NS,
      algorithm: :gcra
    )

    success_count = Concurrent::AtomicFixnum.new(0)
    blocked_count = Concurrent::AtomicFixnum.new(0)

    # Simulate 10 concurrent clients
    threads = 10.times.map do |i|
      Thread.new do
        100.times do
          if fire(limiter)
            success_count.increment
          else
            blocked_count.increment
          end
        end
      end
    end

    threads.each(&:join)

    total = success_count.value + blocked_count.value
    assert_equal 1000, total, "Should process all requests"
    assert_equal 1, success_count.value,
      "Ten threads, one instant, one admission"
  end
end
```

---

## 🎯 Testing Best Practices

### 1. Isolate Time-Dependent Tests
```ruby
def with_frozen_time(start = 1_000 * NS)
  time_machine = TimeMachine.new(start)
  yield(time_machine)
ensure
  time_machine&.return_to_present
end

# Usage
def test_time_sensitive_operation
  with_frozen_time do |time_machine|
    limiter = create_limiter
    use_up_limit(limiter)

    time_machine.advance(30 * NS)
    assert limiter.allow?
  end
end
```

### 2. Test Edge Cases
```ruby
def test_edge_cases
  # Zero limit: refused at construction
  assert_raises(RangeError) do
    ThrottleMachines.limiter("zero", limit: 0, period: 60 * NS)
  end

  # Float seconds: refused at construction
  assert_raises(TypeError) do
    ThrottleMachines.limiter("float", limit: 1, period: 0.001)
  end

  # Massive limit
  huge_limiter = ThrottleMachines.limiter("huge",
    limit: 1_000_000, period: 1 * NS)
  assert huge_limiter.allow?

  # Tiny period: one millisecond
  fast_limiter = ThrottleMachines.limiter("fast",
    limit: 1, period: 1_000_000)
  assert fast_limiter.allow?
end
```

### 3. Test Failure Scenarios
```ruby
StorageOutage = Class.new(StandardError)

# Memory storage that loses its link after `fail_after` counts
class FailingStorage < ThrottleMachines::Storage::Memory
  attr_accessor :fail_after

  def increment_counter(...)
    raise StorageOutage, "Redis went dark" if (self.fail_after -= 1).negative?

    super
  end
end

def test_storage_failure_handling
  # Simulate Redis failure
  failing_storage = FailingStorage.new(auto_cleanup: false)
  failing_storage.fail_after = 5

  # ThrottleMachines.limiter uses the global storage; build one directly
  limiter = ThrottleMachines::Limiter.new("failsafe",
    limit: 10,
    period: 60 * NS,
    algorithm: :fixed_window,
    storage: failing_storage
  )

  5.times { assert fire(limiter) }

  # The limiter does not swallow storage errors: whether to fail open or
  # closed is your call (Storage::Cache offers `fail_closed:`)
  assert_raises(StorageOutage) { limiter.throttle! }
end
```

---

## 🚀 Next Missions

- **[📡 Telemetry](TELEMETRY.md)** - Monitoring test results
- **[🎮 Command Examples](COMMAND_EXAMPLES.md)** - Real-world test scenarios

---

**"In the lab, we break things so they don't break in space."**

*— Chief Science Officer's Testing Manual*
