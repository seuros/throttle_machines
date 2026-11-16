# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in throttle_machines.gemspec.
gemspec

# An untracked Gemfile.local may point sibling gems at local checkouts, to
# test a change there before it is published. It is never committed.
local = File.expand_path('Gemfile.local', __dir__)
eval_gemfile local if File.exist?(local)

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
gem 'rake-compiler', '~> 1.3'
gem 'rbs', '~> 3.0'

platforms :mri do
  gem 'padded_cell', '~> 0.2' # Fork-per-test runner for `rake test` (CRuby only)
end
