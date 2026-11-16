# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rb_sys/extensiontask'
require 'shellwords'

SUPPORTED_NATIVE_PLATFORMS = %w[
  arm64-darwin
  x86_64-darwin
  aarch64-linux
  x86_64-linux
  x86_64-linux-musl
].freeze

GEMSPEC = Gem::Specification.load('throttle_machines.gemspec')

native_ext = RbSys::ExtensionTask.new('throttle_machines_native', GEMSPEC) do |ext|
  ext.lib_dir = 'lib/throttle_machines_native'
  ext.tmp_dir = 'tmp/rb_sys'
  ext.cross_platform = SUPPORTED_NATIVE_PLATFORMS if ENV.key?('RUBY_TARGET')
end

# A single-version cross build stages its binary at the host binary's path,
# which the gem package depends on, so packaging would also compile for the
# host and fail where the host linker can't target the platform (aarch64).
if ENV.key?('RUBY_TARGET')
  host_binary = "#{native_ext.lib_dir}/#{native_ext.name}.#{RbConfig::CONFIG['DLEXT']}"
  Rake::Task[host_binary].clear_prerequisites if Rake::Task.task_defined?(host_binary)
end

namespace :native do
  desc 'Compile the native extension in release mode for the current platform'
  task build: ['rb_sys:env:release', 'compile']

  desc 'Build native gems for all supported platforms'
  task :all do
    SUPPORTED_NATIVE_PLATFORMS.each do |platform|
      sh({ 'RUBY_TARGET' => platform }, 'bundle', 'exec', 'rake', 'native:build')
    end
  end
end

# padded_cell runs each test in its own forked cell.
desc 'Run the test suite in padded_cell cells'
task test: :compile do
  sh 'padded_cell', *Shellwords.split(ENV.fetch('TESTOPTS', ''))
end

desc 'Validate the RBS signatures'
task :rbs do
  sh 'rbs', '-I', 'sig', 'validate'
end

desc 'Run Rust tests'
task :rust_test do
  sh 'cargo test --workspace --all-features'
end

task default: %i[test rbs]

Dir[File.join(__dir__, 'tasks/*.rake')].sort.each { |f| load f }
