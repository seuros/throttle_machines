# frozen_string_literal: true

require_relative 'lib/throttle_machines/version'

Gem::Specification.new do |spec|
  spec.name        = 'throttle_machines'
  spec.version     = ThrottleMachines::VERSION
  spec.authors = ['Abdelkader Boudih']
  spec.email = ['terminale@gmail.com']
  spec.homepage    = 'https://github.com/seuros/throttle_machines'
  spec.summary     = 'Rate limiting (GCRA, token bucket, fixed window) with a native Rust core'
  spec.description = 'ThrottleMachines limits call rates with a no_std Rust core on Integer-nanosecond ' \
                     'clocks, over memory, Redis or cache storage, with Rack and Rails integration.'
  spec.license     = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['cargo_crate_name'] = 'throttle_machines_native'
  spec.metadata['cargo_manifest_path'] = 'ext/throttle_machines_native/ffi/Cargo.toml'

  spec.files = Dir.glob(%w[
    lib/**/*.{rb,lua} sig/**/*.rbs ext/**/*.{rs,rb,toml,md} Cargo.toml
    Cargo.lock README.md CHANGELOG.md LICENSE
  ]).select { |path| File.file?(path) }
    .reject { |path| path.end_with?('/tests.rs') || path.include?('/tests/') }
  spec.require_paths = ['lib']
  spec.extensions = ['ext/throttle_machines_native/extconf.rb']

  spec.add_dependency 'activesupport', '>= 8.1'
  spec.add_dependency 'concurrent-ruby', '~> 1.3'
  spec.add_dependency 'rack', '~> 3.0'
  spec.add_dependency 'rb_sys', '~> 0.9', '>= 0.9.130'
  spec.add_dependency 'zeitwerk', '~> 2.7'

  # Ecosystem dependencies
  spec.add_dependency 'breaker_machines', '>= 0.28.0'
  spec.add_dependency 'chrono_machines', '>= 0.13.0'
  spec.add_dependency 'deadline_machines', '>= 0.2.0'

  spec.required_ruby_version = '>= 4.0.0'
end
