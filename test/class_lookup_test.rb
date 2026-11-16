# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'
require 'rbconfig'

# The classes of the gates the extension wraps (Gcra, TokenBucket,
# FixedWindow) are fixed when it loads. Nothing a caller does later,
# redefining a constant or `Object.const_get`, reaches a gate being built.
# Each case runs in a fresh process: the class is fixed once per process, at
# load.
class ClassLookupTest < Minitest::Test
  LIB = File.expand_path('../lib', __dir__)

  PRELUDE = <<~RUBY
    require 'throttle_machines'
    T = ThrottleMachines
    # Each gate class, captured now, and how to build one of it.
    GATES = {
      Gcra: [T::Gcra, ->(gate) { gate.new(T::GcraPolicy.new(1_000, 0)) }],
      TokenBucket: [T::TokenBucket, ->(gate) { gate.new(T::TokenBucketPolicy.new(1, 1_000)) }],
      FixedWindow: [T::FixedWindow, ->(gate) { gate.new(T::FixedWindowPolicy.new(1_000, 1)) }]
    }
  RUBY

  # Runs `body` after PRELUDE in a new Ruby; answers its last line of output.
  def isolated(body)
    out, err, status = Open3.capture3(RbConfig.ruby, '-I', LIB, '-e', PRELUDE + body)

    assert_predicate status, :success?, "exited #{status.exitstatus}: #{err}"
    out.lines.last&.chomp
  end

  # Bug: a gate built after its constant was redefined was an instance of the
  # new class, so it answered none of the gate's methods.
  def test_a_redefined_constant_does_not_change_the_gate_class
    assert_equal 'true 0 true 0 true 0', isolated(<<~RUBY)
      answers = GATES.flat_map do |name, (original, build)|
        T.send(:remove_const, name)
        T.const_set(name, Class.new)
        gate = build.call(original)
        [gate.instance_of?(original), gate.check(0)]
      end
      puts answers.join(' ')
    RUBY
  end

  # Bug: building the first gate ran `Object.const_get`, Ruby code in the
  # middle of a native call. No Ruby runs to build one now.
  def test_building_a_gate_runs_no_const_get
    assert_equal '0 Gcra TokenBucket FixedWindow', isolated(<<~RUBY)
      hits = 0
      Object.define_singleton_method(:const_get) do |*args|
        hits += 1
        super(*args)
      end
      names = GATES.values.map { |klass, build| build.call(klass).class.name.split('::').last }
      puts [hits, *names].join(' ')
    RUBY
  end

  # Bug: a redefined `Object.const_get` that raised hit an `unwrap` in the
  # extension: an uncatchable fatal, and the process exited.
  def test_a_raising_const_get_does_not_kill_the_process
    assert_equal '0 0 0', isolated(<<~RUBY)
      Object.define_singleton_method(:const_get) { |*| raise IOError, 'lookup ran mid-call' }
      puts GATES.values.map { |klass, build| build.call(klass).check(0) }.join(' ')
    RUBY
  end
end
