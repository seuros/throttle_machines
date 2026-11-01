# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in throttle_machines.gemspec.
gemspec

# Use a sibling checkout when there is one, so a change there is tested here
# before it is published, and the published gem otherwise.
%w[breaker_machines chrono_machines deadline_machines].each do |name|
  sibling = File.expand_path("../#{name}", __dir__)
  gem name, path: sibling if File.directory?(sibling)
end

# Rails version from environment variable (default to 8.1).
# Set RAILS_VERSION=edge to test against rails/rails main.
rails_version = ENV['RAILS_VERSION'] || '8.1'

# Local ecosystem dependencies for development
gem 'minitest', '~> 6.0'
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

platforms :mri do
  gem 'padded_cell', '~> 0.2' # Fork-per-test runner for `rake test` (CRuby only)
  gem 'pg', '~> 1.5'
end
