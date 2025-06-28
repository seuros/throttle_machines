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

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']
  end

  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'concurrent-ruby', '~> 1.3'
  spec.add_dependency 'rack', '~> 3.0'
  spec.add_dependency 'zeitwerk', '~> 2.7'

  # Ecosystem dependencies for retry and circuit breaker functionality
  spec.add_dependency 'breaker_machines', '~> 0.4'
  spec.add_dependency 'chrono_machines', '>= 0.2'

  spec.required_ruby_version = '>= 3.3.0'
end
