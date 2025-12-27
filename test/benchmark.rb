# frozen_string_literal: true

require 'benchmark'
require 'throttle_machines'

# Check if native extension is loaded
native_available = begin
  require 'throttle_machines_native'
  true
rescue LoadError
  false
end

puts "Native extension: #{native_available ? 'LOADED' : 'NOT AVAILABLE (pure Ruby)'}"
puts

ITERATIONS = 100_000

storage = ThrottleMachines::Storage::Memory.new

# Pre-create state for benchmarks
storage.instance_variable_get(:@gcra_states)['bench_gcra'] = { tat: 0.0 }
storage.instance_variable_get(:@token_buckets)['bench_token'] = { tokens: 100.0, last_refill: 0.0 }

Benchmark.bmbm do |x|
  x.report('GCRA check') do
    ITERATIONS.times do |i|
      storage.check_gcra_limit('bench_gcra', 0.1, 0.0, 120)
    end
  end

  x.report('GCRA peek') do
    ITERATIONS.times do
      storage.peek_gcra_limit('bench_gcra', 0.1, 0.0)
    end
  end

  x.report('Token bucket check') do
    ITERATIONS.times do
      storage.check_token_bucket('bench_token', 100.0, 10.0, 120)
    end
  end

  x.report('Token bucket peek') do
    ITERATIONS.times do
      storage.peek_token_bucket('bench_token', 100.0, 10.0)
    end
  end

  x.report('Fixed window increment') do
    ITERATIONS.times do
      storage.increment_counter('bench_window', 60)
    end
  end
end
