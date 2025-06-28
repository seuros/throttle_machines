# frozen_string_literal: true

# Configure instrumentation to write to a log file
require 'fileutils'

# Ensure log directory exists
FileUtils.mkdir_p(Rails.root.join('log'))

# Create instrumentation log file
INSTRUMENTATION_LOG_FILE = Rails.root.join('log', 'instrumentation.log')

# Custom logger for instrumentation events
INSTRUMENTATION_LOGGER = Logger.new(INSTRUMENTATION_LOG_FILE, 'daily')
INSTRUMENTATION_LOGGER.level = Logger::INFO
INSTRUMENTATION_LOGGER.formatter = proc do |severity, datetime, _progname, msg|
  "#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')} [#{severity}] #{msg}\n"
end

# Subscribe to all ThrottleMachines instrumentation events
ActiveSupport::Notifications.subscribe(/\.throttle_machines$/) do |name, start, finish, _id, payload|
  duration = ((finish - start) * 1000).round(2) # Convert to milliseconds

  # Filter out complex objects that can't be serialized to JSON
  filtered_payload = payload.dup
  if filtered_payload[:request]
    # Extract only the essential request info
    req = filtered_payload[:request]
    filtered_payload[:request] = begin
      {
        method: req.request_method,
        path: req.path,
        ip: req.ip,
        user_agent: req.user_agent
      }
    rescue StandardError
      'Unable to serialize request'
    end
  end

  log_data = {
    timestamp: start.strftime('%Y-%m-%d %H:%M:%S.%L'),
    event: name,
    duration_ms: duration,
    payload: filtered_payload
  }

  INSTRUMENTATION_LOGGER.info(log_data.to_json)
end

# Also log to Rails logger for development
if Rails.env.development?
  ActiveSupport::Notifications.subscribe(/\.throttle_machines$/) do |name, start, finish, _id, payload|
    duration = ((finish - start) * 1000).round(2)

    # Filter out request objects from Rails logger too
    filtered_payload = payload.dup
    filtered_payload[:request] = '<Request object>' if filtered_payload[:request]

    Rails.logger.info "[THROTTLE_MACHINES] #{name} - #{filtered_payload.inspect} (#{duration}ms)"
  end
end

Rails.logger.info 'ThrottleMachines instrumentation logging configured'
Rails.logger.info "Instrumentation log file: #{INSTRUMENTATION_LOG_FILE}"
