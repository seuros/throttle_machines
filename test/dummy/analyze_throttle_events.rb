#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'

# Read the instrumentation log
log_file = File.join(__dir__, 'log', 'instrumentation.log')

unless File.exist?(log_file)
  puts "Log file not found: #{log_file}"
  exit 1
end

puts "\n🚀 THROTTLE MACHINES RATE LIMITING ANALYSIS\n"
puts '=' * 80

# Parse events
events = []
File.foreach(log_file) do |line|
  next if line.strip.empty?

  begin
    # Extract JSON from log line
    json_match = line.match(/\{.+\}/)
    next unless json_match

    event = JSON.parse(json_match[0])
    events << event
  rescue JSON::ParserError
    # Skip malformed lines
  end
end

# Group by event type
events.group_by { |e| e['event'] }

# Analyze rate limit events
rate_limit_events = events.select { |e| e['event']&.include?('rate_limit') }

if rate_limit_events.any?
  puts "\n📊 RATE LIMIT SUMMARY"
  puts '-' * 40

  # Group by key
  by_key = rate_limit_events.group_by { |e| e.dig('payload', 'key') }

  by_key.each do |key, key_events|
    puts "\n🔑 Key: #{key}"

    # Get configuration from first event
    first = key_events.first
    limit = first.dig('payload', 'limit')
    period = first.dig('payload', 'period')
    algorithm = first.dig('payload', 'algorithm')

    puts "   Configuration: #{limit} requests per #{period}s (#{algorithm})"

    # Count event types
    checked = key_events.count { |e| e['event'].include?('checked') }
    allowed = key_events.count { |e| e['event'].include?('allowed') }
    throttled = key_events.count { |e| e['event'].include?('throttled') }

    puts "   Total checks: #{checked}"
    puts "   ✅ Allowed: #{allowed}"
    puts "   ❌ Throttled: #{throttled}"

    # Show remaining counts
    remaining_values = key_events
                       .select { |e| e['event'].include?('allowed') }
                       .filter_map { |e| e.dig('payload', 'remaining') }

    if remaining_values.any?
      puts "\n   📉 Remaining count progression:"
      puts "   Starting: #{remaining_values.max}"
      puts "   Ending: #{remaining_values.min}"
      puts '   Rate limit hit at: 0 remaining'
    end

    # Check for rejections
    rejected_checks = key_events.select do |e|
      e['event'].include?('checked') && e.dig('payload', 'allowed') == false
    end

    next unless rejected_checks.any?

    puts "\n   🚫 Rejections after limit:"
    puts "   Count: #{rejected_checks.size}"
    first_rejection = Time.zone.parse(rejected_checks.first['timestamp'])
    last_rejection = Time.zone.parse(rejected_checks.last['timestamp'])
    puts "   Duration: #{(last_rejection - first_rejection).round(2)}s"
  end
end

# Show timeline of the last 20 events
puts "\n\n⏱️  RECENT EVENT TIMELINE"
puts '-' * 40

recent_events = events.last(20)
recent_events.each do |event|
  timestamp = event['timestamp']
  event_type = event['event']&.gsub('.throttle_machines', '') || 'unknown'

  icon = case event_type
         when /allowed/
           '✅'
         when /throttled/
           '❌'
         when /checked/
           event.dig('payload', 'allowed') ? '🔍' : '🚫'
         else
           '📌'
         end

  key = event.dig('payload', 'key')
  remaining = event.dig('payload', 'remaining')
  allowed = event.dig('payload', 'allowed')

  puts "#{timestamp} #{icon} #{event_type}"
  puts "    Key: #{key}"

  puts "    Allowed: #{allowed}" unless allowed.nil?

  puts "    Remaining: #{remaining}" unless remaining.nil?
end

puts "\n✨ Analysis complete!"
