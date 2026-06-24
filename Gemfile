# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in throttle_machines.gemspec.
gemspec

# Rails version from environment variable (default to 8.1).
# Set RAILS_VERSION=edge to test against rails/rails main.
rails_version = ENV['RAILS_VERSION'] || '8.1'

# Local ecosystem dependencies for development
gem 'breaker_machines', '~> 0.12'
gem 'chrono_machines', '>= 0.2.0'
gem 'minitest'
gem 'mock_redis', '~> 0.44'
gem 'puma'
if rails_version == 'edge'
  git 'https://github.com/rails/rails.git', branch: 'main' do
    gem 'actionpack'
    gem 'actionview'
    gem 'activesupport'
    gem 'railties'
  end
else
  gem 'activesupport'
  gem 'railties', "~> #{rails_version}.0"
end
gem 'rake'
gem 'rubocop'
gem 'rubocop-minitest'
gem 'rubocop-performance'
gem 'rubocop-rails'
gem 'rubocop-rake'

platforms :mri do
  gem 'pg', '~> 1.5'
end
