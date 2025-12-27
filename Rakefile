# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb'].exclude('test/dummy/**/*')
  t.verbose = false
end

desc 'Benchmark native vs pure Ruby implementation'
task :bench do
  puts '=== Pure Ruby ==='
  system({ 'DISABLE_THROTTLE_MACHINES_NATIVE' => '1' }, 'ruby', '-Ilib', 'test/benchmark.rb')

  puts ''
  puts '=== Native (Rust) ==='
  system('ruby', '-Ilib', 'test/benchmark.rb')
end

desc 'Run Rust tests'
task :rust_test do
  Dir.chdir('ext/throttle_machines_native') do
    sh 'cargo test'
  end
end

task default: :test
