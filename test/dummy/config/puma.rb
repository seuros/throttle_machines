# frozen_string_literal: true

# Puma configuration for throttle_machines dummy app

# Threads
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)
threads threads_count, threads_count

# Port
port ENV.fetch('PORT', 3000)

# Environment
environment ENV.fetch('RAILS_ENV', 'development')

# Workers (useful for testing concurrent requests)
workers ENV.fetch('WEB_CONCURRENCY', 2) if ENV['RAILS_ENV'] == 'production'

# Preload app for performance
preload_app!

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart
