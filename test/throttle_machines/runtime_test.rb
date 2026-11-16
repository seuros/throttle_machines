# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'rack'
require 'throttle_machines/controller_helpers'

module ThrottleMachines
  # The runtime layered on the gates: Integer nanoseconds end to end, whole
  # seconds only in HTTP headers.
  class RuntimeTest < Test
    def setup
      super
      @clock = TestClock.new
    end

    def teardown
      @clock.reset
      super
    end

    def test_the_clock_is_integer_nanoseconds
      @clock.reset

      assert_kind_of Integer, ThrottleMachines.monotonic_time
    end

    def test_breakers_shape_the_policy_in_nanoseconds
      policy = Breakers.policy(3, 10 * NS, 5 * NS)

      assert_equal [3, nil, 0], policy.threshold.to_h.values
      assert_equal 10 * NS, policy.window
      assert_equal [5 * NS, 0.0, 1, 1], policy.recovery.to_h.values
      assert_nil policy.max_concurrent
    end

    def test_breakers_measure_the_ban_on_the_circuit_clock
      now = 1_000 * NS
      circuit = BreakerMachines::Circuit.new('rt:since', Breakers.policy(1, 10 * NS, 5 * NS),
                                             clock: -> { now }, auto_register: false)

      assert_nil Breakers.since(circuit)
      assert_raises(IOError) { circuit.call { raise IOError } }
      now += 2 * NS

      assert_equal 2 * NS, Breakers.since(circuit)
      assert_equal 3 * NS, circuit.retry_after
    end

    def test_break_circuit_shares_one_registry_circuit
      guarded = ->(&block) { ThrottleMachines.break_circuit('rt:shared', failures: 2, within: 60 * NS, &block) }
      2.times { assert_raises(IOError) { guarded.call { raise IOError } } }

      error = assert_raises(CircuitOpenError) { guarded.call { :never } }

      assert_kind_of BreakerMachines::CircuitRefusedError, error
      assert_equal 60 * NS, BreakerMachines::Registry.instance.get_or_create_dynamic_circuit('rt:shared', nil, nil)
                                                           .policy.recovery.cooldown
    ensure
      BreakerMachines::Registry.instance.remove_dynamic_circuit('rt:shared')
    end

    def test_fail2ban_bans_for_bantime_and_allow2ban_lifts_it
      require 'throttle_machines/rack_middleware'
      options = { maxretry: 2, findtime: 60 * NS, bantime: 300 * NS }
      fail2ban = RackMiddleware::Fail2Ban.new('rt:login', options, &:ip)
      allow2ban = RackMiddleware::Allow2Ban.new('rt:login', options, &:ip)
      request = -> { Rack::Request.new(Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => '10.9.8.7')) }
      now = 1_000 * NS
      # The circuit the filters share, seeded with a clock the test turns.
      Breakers.dynamic('fail2ban:rt:login:10.9.8.7', self, 2, 60 * NS, 300 * NS, clock: -> { now })

      2.times { fail2ban.count(request.call) { true } }
      now += 30 * NS
      banned = request.call

      assert fail2ban.banned?(banned)
      assert_equal({ discriminator: '10.9.8.7', maxretry: 2, findtime: 60 * NS, bantime: 300 * NS, failures: 2,
                     time_until_unban: 270 * NS }, banned.env['rack.attack.match_data'])

      3.times { refute allow2ban.matched_by?(request.call) }

      refute fail2ban.banned?(request.call)
    ensure
      BreakerMachines::Registry.instance.remove_dynamic_circuit('fail2ban:rt:login:10.9.8.7')
    end

    %i[fixed_window gcra token_bucket].each do |algorithm|
      define_method("test_#{algorithm}_limiter_reports_in_nanoseconds") do
        limiter = ThrottleMachines.limiter("rt:#{algorithm}", limit: 2, period: 10 * NS, algorithm: algorithm)

        # GCRA spreads the two calls 5 s apart; the others admit both at once.
        burst = algorithm == :gcra ? 1 : 2

        assert_equal burst, limiter.remaining
        burst.times { limiter.throttle! }

        assert_equal 0, limiter.remaining
        assert_raises(ThrottledError) { limiter.throttle! }
        assert_operator limiter.retry_after, :>, 0
        assert_operator limiter.retry_after, :<=, 10 * NS
        assert_equal({ key: "rt:#{algorithm}", limit: 2, period: 10 * NS, algorithm: algorithm, remaining: 0,
                       retry_after: limiter.retry_after }, limiter.to_h)
        assert_predicate limiter, :frozen?
      end
    end

    def test_a_gcra_limiter_waits_exactly_one_interval
      limiter = ThrottleMachines.limiter('rt:exact', limit: 4, period: NS, algorithm: :gcra)
      limiter.throttle!

      assert_equal 250 * MS, limiter.retry_after
      @clock.advance(250 * MS)

      assert_nil limiter.throttle!
    end

    def test_the_null_store_admits_everything
      store = Storage::Null.new
      gcra = GcraPolicy.per(NS, 1, 3)
      bucket = TokenBucketPolicy.new(4, NS)

      assert_equal [2, 3, 0],
                   [store.check_gcra('k', gcra, NS), store.peek_gcra('k', gcra), store.gcra_retry_after('k', gcra)]
      assert_equal [3, 4, 0], [store.check_token_bucket('k', bucket, NS), store.peek_token_bucket('k', bucket),
                               store.token_bucket_retry_after('k', bucket)]
      assert_equal [0, 0, 0],
                   [store.increment_counter('k', NS), store.get_counter('k', NS), store.get_counter_ttl('k', NS)]
      assert [store.reset_gcra('k'), store.reset_token_bucket('k'), store.reset_counter('k', NS),
              store.clear, store.reset_key('k')].all?
      assert_predicate store, :healthy?
    end

    def test_with_timeout_takes_nanoseconds
      store = Storage::Null.new

      assert_equal :done, store.with_timeout(NS) { :done }
      assert_raises(Timeout::Error) { store.with_timeout(10 * MS) { sleep 1 } }
    end

    # Reproduces a bug: the timeout path raised the long-removed
    # ::TimeoutError, so a timed-out hedge surfaced as NameError.
    def test_a_hedged_request_that_times_out_raises_a_timeout_error
      @clock.reset
      hedged = HedgedRequest.new(delay: 10 * MS, max_attempts: 1, timeout: 20 * MS)
      release = Queue.new

      error = assert_raises(Timeout::Error) { hedged.run { release.pop } }
      assert_match(/timed out/, error.message)
    ensure
      release&.push(true)
      hedged&.shutdown
    end

    def test_hedged_spans_are_integer_nanoseconds
      assert_raises(TypeError) { HedgedRequest.new(delay: 0.05) }
      assert_raises(RangeError) { HedgedRequest.new(timeout: -1) }
      assert_equal :ok, ThrottleMachines.hedged_request(delay: MS, max_attempts: 1) { :ok }
    end

    # Reproduces a bug: `hedged_request` was defined in the autoloaded
    # hedged_request.rb, so it did not exist until something named
    # HedgedRequest. A fresh process proves it is there right after require.
    def test_hedged_request_exists_before_hedged_request_is_named
      lib = File.expand_path('../../lib', __dir__)
      script = "require 'throttle_machines'; p ThrottleMachines.hedged_request(delay: 0, max_attempts: 1) { :ok }"
      out, err, status = Open3.capture3(RbConfig.ruby, '-I', lib, '-e', script)

      assert_predicate status, :success?, err
      assert_equal ":ok\n", out
    end

    def test_a_hedged_breaker_runs_through_its_breakers
      @clock.reset
      breaker = Object.new
      breaker.define_singleton_method(:call) { |&block| block.call }

      assert_equal :through, HedgedBreaker.new([breaker], delay: MS).run { :through }
    end

    def test_the_middleware_answers_retry_after_in_whole_seconds
      app = ->(_env) { [200, {}, ['OK']] }
      middleware = Middleware.new(app) { throttle '/api', limit: 1, period: 1_500 * MS, by: ->(_req) { 'one' } }
      env = Rack::MockRequest.env_for('/api')

      assert_equal 200, middleware.call(env).first
      ThrottleMachines.limiter('one', limit: 1, period: 1_500 * MS, algorithm: :gcra).throttle! rescue nil
      status, headers, body = middleware.call(Rack::MockRequest.env_for('/api'))

      assert_equal 429, status
      assert_equal '2', headers['Retry-After']
      assert_equal({ 'error' => 'Rate limit exceeded', 'retry_after' => 2 }, JSON.parse(body.first))
    end

    # A stand-in for a controller: just what the helpers call.
    class FakeController
      include ControllerHelpers

      Response = Struct.new(:headers)
      attr_reader :response, :rendered

      def initialize
        @response = Response.new({})
      end

      def current_user = nil
      def request = Struct.new(:remote_ip).new('10.0.0.1')
      def respond_to = yield(self)
      def json = yield
      def html = nil
      def render(**options) = (@rendered = options)
    end

    # Reproduces a bug: throttle! only peeked, so it never spent a call and
    # never throttled anyone.
    def test_controller_throttle_bang_spends_a_call
      controller = FakeController.new

      controller.throttle!('rt:spend', limit: 1, period: 3 * NS, algorithm: :fixed_window)

      assert_nil controller.rendered
      assert_equal '0', controller.response.headers['X-RateLimit-Remaining']

      controller.throttle!('rt:spend', limit: 1, period: 3 * NS, algorithm: :fixed_window)

      assert_equal :too_many_requests, controller.rendered[:status]
    end

    def test_controller_helpers_limit_and_report_in_whole_seconds
      controller = FakeController.new

      assert_equal 1, controller.rate_limit_remaining(limit: 1, period: 3 * NS)
      refute controller.rate_limited?(limit: 1, period: 3 * NS)
      assert_equal :ran, controller.with_throttle(limit: 1, period: 3 * NS) { :ran }
      assert controller.rate_limited?(limit: 1, period: 3 * NS)

      controller.throttle!(limit: 1, period: 3 * NS, algorithm: :fixed_window)

      assert_equal :too_many_requests, controller.rendered[:status]
      assert_equal 3, controller.rendered[:json][:retry_after]
      assert_equal '3', controller.response.headers['Retry-After']
    end
  end
end
