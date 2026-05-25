# frozen_string_literal: true

require_relative 'lib/throttle_machines/version'

Gem::Specification.new do |spec|
  spec.name        = 'throttle_machines'
  spec.version     = ThrottleMachines::VERSION
  spec.authors = ['Abdelkader Boudih']
  spec.email = ['terminale@gmail.com']
  spec.homepage    = 'https://github.com/seuros/throttle_machines'
  spec.summary     = 'Advanced Rate limiting for Ruby applications'
  spec.description = 'ThrottleMachines provides ultra-thin, elegant rate limiting with temporal precision for distributed systems.'
  spec.license     = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['cargo_crate_name'] = 'throttle_machines_native'
  spec.metadata['cargo_manifest_path'] = 'ext/throttle_machines_native/ffi/Cargo.toml'

  # The generic `ruby` gem is pure Ruby; native binaries are shipped only in
  # platform gems built by rb_sys.
  lib_files = Dir['lib/**/*'].reject { |path| path =~ /\.(bundle|so|dll)\z/ }
  spec.files = lib_files + %w[LICENSE README.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 8.0.4'
  spec.add_dependency 'concurrent-ruby', '~> 1.3'
  spec.add_dependency 'rack', '~> 3.0'
  spec.add_dependency 'zeitwerk', '~> 2.7'

  # Ecosystem dependencies - require Rails 8.0.4+ compatible versions
  spec.add_dependency 'breaker_machines', '~> 0.12'
  spec.add_dependency 'chrono_machines', '>= 0.2'

  spec.add_development_dependency 'minitest', '~> 5.16'
  spec.add_development_dependency 'rb_sys', '~> 0.9'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rake-compiler', '~> 1.3'

  spec.required_ruby_version = '>= 3.3.0'
end
