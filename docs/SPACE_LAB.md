# 🔬 Space Lab

> **Testing in Zero Gravity** - Because in space, nobody can hear your tests fail

Welcome to the ThrottleMachines testing laboratory! Here we'll learn how to test your rate limiters, circuit breakers, and defensive systems without actually launching into the void.

---

## 🧪 Basic Test Equipment

### Setting Up Your Lab
```ruby
# test/test_helper.rb or spec/spec_helper.rb
require 'throttle_machines'
require 'minitest/autorun'  # or 'rspec'

class ThrottleTest < Minitest::Test
  def setup
    # Reset the universe before each test
    ThrottleMachines.reset!
    
    # Use memory storage for speed
    ThrottleMachines.configure do |config|
      config.storage = ThrottleMachines::Storage::Memory.new
    end
    
    # Freeze time for predictable tests
    @time_machine = TimeMachine.new
  end
  
  def teardown
    @time_machine.return_to_present
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
    launcher = ThrottleMachines.limiter("torpedoes", limit: 3, period: 10)
    
    # Fire all torpedoes
    3.times do |i|
      assert launcher.allowed?, "Shot #{i+1} should be allowed"
    end
    
    # Fourth shot should fail
    refute launcher.allowed?, "Fourth shot should be blocked"
    
    # Check retry timing
    assert_in_delta 10, launcher.retry_after, 0.1
  end
  
  def test_rate_limit_reset
    launcher = ThrottleMachines.limiter("torpedoes", limit: 2, period: 5)
    
    # Use up all shots
    2.times { launcher.allowed? }
    refute launcher.allowed?
    
    # Travel through time
    @time_machine.advance(5.seconds)
    
    # Torpedoes recharged!
    assert launcher.allowed?, "Should reset after period"
  end
end
```

### Testing Different Algorithms
```ruby
class AlgorithmComparisonTest < ThrottleTest
  def test_fixed_window_hard_reset
    limiter = ThrottleMachines.limiter("fixed_test",
      limit: 100,
      period: 60,
      algorithm: :fixed_window
    )
    
    # Use 99 requests
    99.times { limiter.allowed? }
    assert limiter.allowed?  # 100th request
    refute limiter.allowed?  # 101st blocked
    
    # Jump to just before window end
    @time_machine.advance(59.seconds)
    refute limiter.allowed?  # Still blocked
    
    # Window resets exactly at boundary
    @time_machine.advance(1.second)
    assert limiter.allowed?  # Fresh window!
  end
  
  def test_token_bucket_regeneration
    bucket = ThrottleMachines.limiter("token_test",
      limit: 10,      # 10 tokens max
      period: 10,     # Refill in 10 seconds
      algorithm: :token_bucket
    )
    
    # Empty the bucket
    10.times { bucket.allowed? }
    refute bucket.allowed?
    
    # Wait for partial refill
    @time_machine.advance(5.seconds)
    
    # Should have ~5 tokens now
    5.times do |i|
      assert bucket.allowed?, "Token #{i+1} should be available"
    end
    refute bucket.allowed?, "Bucket should be empty again"
  end
  
  def test_gcra_smooth_distribution
    gcra = ThrottleMachines.limiter("gcra_test",
      limit: 60,
      period: 60,
      algorithm: :gcra
    )
    
    # GCRA prevents bursts and distributes evenly
    # Each request should be spaced ~1 second apart
    
    assert gcra.allowed?  # First is free
    
    # Second request immediately should fail
    refute gcra.allowed?, "GCRA prevents immediate burst"
    
    # But after 1 second, should allow
    @time_machine.advance(1.second)
    assert gcra.allowed?
  end
end
```

---

## 🛡️ Testing Circuit Breakers

### Basic Shield Testing
```ruby
class ShieldSystemTest < ThrottleTest
  def setup
    super
    @shields = ThrottleMachines::Breaker.new("test_shields",
      failure_threshold: 3,
      reset_timeout: 10,
      storage: ThrottleMachines.configuration.storage
    )
  end
  
  def test_shield_activation
    # Normal operation
    assert_nothing_raised do
      @shields.run { "Success" }
    end
    
    # Simulate 3 failures
    3.times do |i|
      assert_raises(RuntimeError) do
        @shields.run { raise "System failure #{i+1}" }
      end
    end
    
    # Shields should now be UP
    assert_raises(ThrottleMachines::CircuitOpenError) do
      @shields.run { "This won't execute" }
    end
  end
  
  def test_shield_recovery
    # Trigger shield activation
    3.times do
      @shields.run { raise "Failure" } rescue nil
    end
    
    # Shields are up
    assert_raises(ThrottleMachines::CircuitOpenError) do
      @shields.run { "Blocked" }
    end
    
    # Wait for cooldown
    @time_machine.advance(10.seconds)
    
    # Shields should attempt recovery (half-open)
    assert_equal "Success", @shields.run { "Success" }
    
    # Shields fully lowered after success
    assert_equal "Normal operation", @shields.run { "Normal operation" }
  end
  
  def test_shield_reactivation
    # Activate shields
    3.times { @shields.run { raise "Error" } rescue nil }
    
    # Wait for recovery
    @time_machine.advance(10.seconds)
    
    # First call succeeds (half-open -> closed)
    @shields.run { "Success" }
    
    # But if we fail again...
    assert_raises(RuntimeError) do
      @shields.run { raise "Another failure!" }
    end
    
    # Shields immediately go back up (half-open -> open)
    assert_raises(ThrottleMachines::CircuitOpenError) do
      @shields.run { "Blocked again" }
    end
  end
end
```

### Advanced Shield Patterns
```ruby
class AdvancedShieldTest < ThrottleTest
  def test_cascading_shields
    primary = ThrottleMachines::Breaker.new("primary", 
      failure_threshold: 5, reset_timeout: 10)
    secondary = ThrottleMachines::Breaker.new("secondary", 
      failure_threshold: 3, reset_timeout: 20)
    
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
    
    # Configure middleware for testing
    ThrottleMachines::RackMiddleware.configure do |config|
      config.throttle("test_limit", limit: 3, period: 60) do |req|
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
    assert last_response.headers["Retry-After"]
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
class TimeMachine
  def initialize
    @original_now = Time.method(:now)
    @current_time = Time.now
    
    # Monkey patch Time.now for testing
    Time.define_singleton_method(:now) { @current_time }
    Time.define_singleton_method(:current) { @current_time }
  end
  
  def advance(duration)
    @current_time += duration
  end
  
  def rewind(duration)
    @current_time -= duration
  end
  
  def freeze
    # Time already frozen at @current_time
  end
  
  def return_to_present
    # Restore original Time.now
    Time.define_singleton_method(:now, &@original_now)
    Time.singleton_class.remove_method(:current) if Time.respond_to?(:current)
  end
end
```

### Custom Assertions
```ruby
module ThrottleAssertions
  def assert_throttled(limiter, message = nil)
    refute limiter.allowed?, message || "Expected to be throttled"
  end
  
  def assert_not_throttled(limiter, message = nil)
    assert limiter.allowed?, message || "Expected not to be throttled"
  end
  
  def assert_retry_after_between(limiter, min, max, message = nil)
    retry_after = limiter.retry_after
    assert retry_after >= min && retry_after <= max,
      message || "Expected retry_after between #{min} and #{max}, got #{retry_after}"
  end
  
  def assert_circuit_open(breaker, message = nil)
    assert_equal :open, breaker.status_name,
      message || "Expected circuit to be open"
  end
  
  def assert_circuit_closed(breaker, message = nil)
    assert_equal :closed, breaker.status_name,
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
require 'benchmark'

class PerformanceLab < ThrottleTest
  def test_algorithm_performance
    iterations = 10_000
    
    algorithms = {
      fixed_window: :fixed_window,
      token_bucket: :token_bucket,
      gcra: :gcra,
      sliding_window: :sliding_window
    }
    
    results = {}
    
    algorithms.each do |name, algorithm|
      limiter = ThrottleMachines.limiter("perf_#{name}",
        limit: 1000,
        period: 60,
        algorithm: algorithm
      )
      
      # Warm up
      100.times { limiter.allowed? }
      
      # Benchmark
      time = Benchmark.realtime do
        iterations.times { limiter.allowed? }
      end
      
      results[name] = {
        total_time: time,
        ops_per_second: (iterations / time).round,
        time_per_op_us: ((time / iterations) * 1_000_000).round(2)
      }
    end
    
    # Print results
    puts "\nAlgorithm Performance Comparison:"
    puts "-" * 50
    results.each do |name, metrics|
      puts "#{name}:"
      puts "  Ops/second: #{metrics[:ops_per_second]}"
      puts "  Time/op: #{metrics[:time_per_op_us]}μs"
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
    limiter = ThrottleMachines.limiter("concurrent_test",
      limit: 1000,
      period: 1,
      algorithm: :gcra
    )
    
    success_count = Concurrent::AtomicFixnum.new(0)
    blocked_count = Concurrent::AtomicFixnum.new(0)
    
    # Simulate 10 concurrent clients
    threads = 10.times.map do |i|
      Thread.new do
        100.times do
          if limiter.allowed?
            success_count.increment
          else
            blocked_count.increment
          end
          sleep 0.001  # Small delay
        end
      end
    end
    
    threads.each(&:join)
    
    total = success_count.value + blocked_count.value
    assert_equal 1000, total, "Should process all requests"
    assert_operator success_count.value, :<=, 1000, 
      "Should not exceed limit"
  end
end
```

---

## 🎯 Testing Best Practices

### 1. Isolate Time-Dependent Tests
```ruby
def with_frozen_time(time = Time.now)
  time_machine = TimeMachine.new
  yield(time_machine)
ensure
  time_machine.return_to_present
end

# Usage
def test_time_sensitive_operation
  with_frozen_time do |time_machine|
    limiter = create_limiter
    use_up_limit(limiter)
    
    time_machine.advance(30.seconds)
    assert limiter.allowed?
  end
end
```

### 2. Test Edge Cases
```ruby
def test_edge_cases
  # Zero limit
  zero_limiter = ThrottleMachines.limiter("zero", limit: 0, period: 60)
  refute zero_limiter.allowed?
  
  # Massive limit
  huge_limiter = ThrottleMachines.limiter("huge", 
    limit: 1_000_000, period: 1)
  assert huge_limiter.allowed?
  
  # Tiny period
  fast_limiter = ThrottleMachines.limiter("fast", 
    limit: 1, period: 0.001)
  assert fast_limiter.allowed?
end
```

### 3. Test Failure Scenarios
```ruby
def test_storage_failure_handling
  # Simulate Redis failure
  failing_storage = MockStorage.new(fail_after: 5)
  
  limiter = ThrottleMachines.limiter("failsafe",
    limit: 10,
    period: 60,
    storage: failing_storage
  )
  
  # Should handle storage failures gracefully
  10.times do |i|
    if i < 5
      assert limiter.allowed?
    else
      # After storage fails, might fail open or closed
      # depending on your implementation
      begin
        limiter.allowed?
      rescue => e
        assert_kind_of ThrottleMachines::StorageError, e
      end
    end
  end
end
```

---

## 🚀 Next Missions

- **[📡 Telemetry](TELEMETRY.md)** - Monitoring test results
- **[🎮 Command Examples](COMMAND_EXAMPLES.md)** - Real-world test scenarios

---

**"In the lab, we break things so they don't break in space."**

*— Chief Science Officer's Testing Manual*
