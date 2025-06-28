#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'
require 'optparse'

# Log Analyzer for ThrottleMachines Instrumentation Events
class InstrumentationLogAnalyzer
  attr_reader :log_file, :events, :options

  def initialize(log_file = nil, options = {})
    @log_file = log_file || File.join(__dir__, 'log', 'instrumentation.log')
    @events = []
    @options = {
      verbose: false,
      filter_event: nil,
      filter_key: nil,
      time_range: nil,
      show_stats: true,
      show_timeline: true,
      show_summary: true,
      format: :pretty
    }.merge(options)
  end

  def analyze!
    parse_log_file
    filter_events

    if options[:format] == :json
      output_json
    else
      output_pretty
    end
  end

  private

  def parse_log_file
    unless File.exist?(log_file)
      puts "❌ Log file not found: #{log_file}"
      puts 'Make sure the Rails server has been running and generating events.'
      exit 1
    end

    puts "📖 Parsing log file: #{log_file}"

    File.readlines(log_file).each_with_index do |line, index|
      next if line.strip.empty?

      begin
        # Extract JSON from log line (format: "timestamp [level] json")
        json_match = line.match(/\[INFO\]\s+(.+)$/)
        next unless json_match

        event_data = JSON.parse(json_match[1])
        event_data['line_number'] = index + 1
        events << event_data
      rescue JSON::ParserError => e
        puts "⚠️  Failed to parse line #{index + 1}: #{e.message}" if options[:verbose]
      end
    end

    puts "✅ Parsed #{events.size} events"
  end

  def filter_events
    filtered = events

    # Filter by event type
    if options[:filter_event]
      filtered = filtered.select { |e| e['event']&.include?(options[:filter_event]) }
      puts "🔍 Filtered to #{filtered.size} events matching '#{options[:filter_event]}'"
    end

    # Filter by key
    if options[:filter_key]
      filtered = filtered.select { |e| e.dig('payload', 'key')&.include?(options[:filter_key]) }
      puts "🔍 Filtered to #{filtered.size} events with key matching '#{options[:filter_key]}'"
    end

    # Filter by time range
    if options[:time_range]
      start_time, end_time = options[:time_range]
      filtered = filtered.select do |e|
        event_time = Time.zone.parse(e['timestamp'])
        event_time.between?(start_time, end_time)
      end
      puts "🔍 Filtered to #{filtered.size} events in time range"
    end

    @events = filtered
  end

  def output_json
    puts JSON.pretty_generate({
                                meta: {
                                  total_events: events.size,
                                  log_file: log_file,
                                  analyzed_at: Time.now.iso8601
                                },
                                events: events
                              })
  end

  def output_pretty
    puts "\n#{'=' * 80}"
    puts '📊 THROTTLE MACHINES INSTRUMENTATION ANALYSIS'
    puts '=' * 80

    show_summary_stats if options[:show_summary]
    show_event_timeline if options[:show_timeline]
    show_detailed_stats if options[:show_stats]
    show_rate_limit_analysis
    show_circuit_breaker_analysis if has_circuit_events?
  end

  def show_summary_stats
    puts "\n📈 SUMMARY STATISTICS"
    puts '-' * 40

    event_types = events.group_by { |e| e['event'] }

    puts "Total Events: #{events.size}"
    puts 'Event Types:'
    event_types.each do |type, type_events|
      puts "  #{type}: #{type_events.size}"
    end

    return unless events.any?

    first_event = Time.zone.parse(events.first['timestamp'])
    last_event = Time.zone.parse(events.last['timestamp'])
    duration = last_event - first_event

    puts "\nTime Range:"
    puts "  First Event: #{first_event.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "  Last Event:  #{last_event.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "  Duration:    #{duration.round(2)} seconds"

    return unless duration.positive?

    rate = events.size / duration
    puts "  Event Rate:  #{rate.round(2)} events/second"
  end

  def show_event_timeline
    return if events.empty?

    puts "\n⏱️  EVENT TIMELINE"
    puts '-' * 40

    events.each do |event|
      timestamp = Time.zone.parse(event['timestamp'])
      event_name = event['event'].split('.').last
      payload = event['payload'] || {}

      icon = event_icon(event['event'])
      color = event_color(event['event'])

      puts "#{timestamp.strftime('%H:%M:%S.%L')} #{icon} #{color}#{event_name}#{reset_color}"

      if options[:verbose]
        payload.each do |key, value|
          puts "    #{key}: #{value}"
        end
      else
        # Show key information based on event type
        case event['event']
        when /rate_limit/
          key = payload['key']
          if payload['allowed']
            remaining = payload['remaining'] || 'unknown'
            puts "    ✅ #{key} - #{remaining} remaining"
          else
            retry_after = payload['retry_after'] || 'unknown'
            puts "    ❌ #{key} - throttled (retry after #{retry_after}s)"
          end
        when /circuit_breaker/
          key = payload['key']
          state = payload['state']
          puts "    🔌 #{key} - #{state}"
        end
      end
    end
  end

  def show_detailed_stats
    puts "\n📊 DETAILED STATISTICS"
    puts '-' * 40

    # Rate limit statistics
    rate_limit_events = events.select { |e| e['event'].include?('rate_limit') }
    if rate_limit_events.any?
      puts "\nRate Limiting:"

      # Group by key
      by_key = rate_limit_events.group_by { |e| e.dig('payload', 'key') }
      by_key.each do |key, key_events|
        allowed = key_events.count { |e| e.dig('payload', 'allowed') }
        throttled = key_events.count { |e| !e.dig('payload', 'allowed') }
        total = key_events.size

        rate = total.positive? ? (throttled.to_f / total * 100).round(1) : 0
        puts "  #{key}:"
        puts "    Total: #{total}, Allowed: #{allowed}, Throttled: #{throttled} (#{rate}%)"

        # Show limit/period info from first event
        first_event = key_events.first
        next unless first_event && first_event['payload']

        limit = first_event.dig('payload', 'limit')
        period = first_event.dig('payload', 'period')
        algorithm = first_event.dig('payload', 'algorithm')
        puts "    Config: #{limit} req/#{period}s (#{algorithm})"
      end
    end

    # Algorithm distribution
    algorithms = rate_limit_events.filter_map { |e| e.dig('payload', 'algorithm') }
    if algorithms.any?
      puts "\nAlgorithm Distribution:"
      algorithm_counts = algorithms.group_by(&:itself).transform_values(&:size)
      algorithm_counts.each do |algorithm, count|
        puts "  #{algorithm}: #{count} events"
      end
    end

    # Response time analysis
    response_times = events.filter_map { |e| e['duration_ms'] }
    return unless response_times.any?

    puts "\nResponse Times (ms):"
    puts "  Min: #{response_times.min}"
    puts "  Max: #{response_times.max}"
    puts "  Avg: #{(response_times.sum.to_f / response_times.size).round(2)}"

    # Percentiles
    sorted = response_times.sort
    p95_index = (sorted.size * 0.95).to_i
    p99_index = (sorted.size * 0.99).to_i
    puts "  P95: #{sorted[p95_index]}"
    puts "  P99: #{sorted[p99_index]}"
  end

  def show_rate_limit_analysis
    rate_limit_events = events.select { |e| e['event'].include?('rate_limit') }
    return if rate_limit_events.empty?

    puts "\n🚦 RATE LIMIT ANALYSIS"
    puts '-' * 40

    # Time-based analysis
    puts "\nThrottling Timeline:"
    throttled_events = rate_limit_events.reject { |e| e.dig('payload', 'allowed') }

    if throttled_events.any?
      throttled_events.each do |event|
        timestamp = Time.zone.parse(event['timestamp'])
        key = event.dig('payload', 'key')
        retry_after = event.dig('payload', 'retry_after')

        puts "  #{timestamp.strftime('%H:%M:%S')} - #{key} throttled (retry: #{retry_after}s)"
      end
    else
      puts '  ✅ No throttling detected'
    end

    # Burst detection
    puts "\nBurst Analysis:"
    by_key = rate_limit_events.group_by { |e| e.dig('payload', 'key') }
    by_key.each do |key, key_events|
      # Look for rapid requests (within 1 second windows)
      times = key_events.map { |e| Time.zone.parse(e['timestamp']) }.sort
      bursts = []

      i = 0
      while i < times.size
        window_end = times[i] + 1 # 1 second window
        window_events = times[i..].take_while { |t| t <= window_end }

        if window_events.size > 3 # More than 3 requests in 1 second
          bursts << { start: times[i], count: window_events.size }
        end

        i += 1
      end

      if bursts.any?
        puts "  #{key}: #{bursts.size} burst(s) detected"
        bursts.each do |burst|
          puts "    #{burst[:start].strftime('%H:%M:%S')} - #{burst[:count]} requests/second"
        end
      else
        puts "  #{key}: No bursts detected"
      end
    end
  end

  def show_circuit_breaker_analysis
    circuit_events = events.select { |e| e['event'].include?('circuit_breaker') }
    return if circuit_events.empty?

    puts "\n⚡ CIRCUIT BREAKER ANALYSIS"
    puts '-' * 40

    by_key = circuit_events.group_by { |e| e.dig('payload', 'key') }
    by_key.each do |key, key_events|
      puts "\n#{key}:"

      state_changes = key_events.select { |e| %w[opened closed half_opened].any? { |s| e['event'].include?(s) } }
      if state_changes.any?
        puts '  State Changes:'
        state_changes.each do |event|
          timestamp = Time.zone.parse(event['timestamp'])
          state = event['event'].split('.').last
          puts "    #{timestamp.strftime('%H:%M:%S')} - #{state}"
        end
      end

      failures = key_events.count { |e| e['event'].include?('failure') }
      successes = key_events.count { |e| e['event'].include?('success') }
      total = failures + successes

      if total.positive?
        failure_rate = (failures.to_f / total * 100).round(1)
        puts "  Success/Failure: #{successes}/#{failures} (#{failure_rate}% failure rate)"
      end
    end
  end

  def has_circuit_events?
    events.any? { |e| e['event'].include?('circuit_breaker') }
  end

  def event_icon(event_name)
    case event_name
    when /rate_limit.*allowed/ then '✅'
    when /rate_limit.*throttled/ then '🛑'
    when /rate_limit.*checked/ then '🔍'
    when /circuit_breaker.*opened/ then '🔴'
    when /circuit_breaker.*closed/ then '🟢'
    when /circuit_breaker.*half_opened/ then '🟡'
    when /circuit_breaker.*success/ then '✅'
    when /circuit_breaker.*failure/ then '❌'
    when /circuit_breaker.*rejected/ then '🚫'
    when /cascade/ then '🌊'
    when /hedged_request/ then '🎯'
    else '📊'
    end
  end

  def event_color(_event_name)
    '' # Simplified for now - could add ANSI colors
  end

  def reset_color
    ''
  end
end

# Command line interface
if __FILE__ == $PROGRAM_NAME
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] [log_file]"

    opts.on('-v', '--verbose', 'Show verbose output') do
      options[:verbose] = true
    end

    opts.on('-e', '--event EVENT', 'Filter by event type (partial match)') do |event|
      options[:filter_event] = event
    end

    opts.on('-k', '--key KEY', 'Filter by rate limit key (partial match)') do |key|
      options[:filter_key] = key
    end

    opts.on('-j', '--json', 'Output in JSON format') do
      options[:format] = :json
    end

    opts.on('--no-stats', 'Skip detailed statistics') do
      options[:show_stats] = false
    end

    opts.on('--no-timeline', 'Skip event timeline') do
      options[:show_timeline] = false
    end

    opts.on('--no-summary', 'Skip summary') do
      options[:show_summary] = false
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      puts "\nExamples:"
      puts "  #{$PROGRAM_NAME}                           # Analyze default log file"
      puts "  #{$PROGRAM_NAME} -v                        # Verbose output"
      puts "  #{$PROGRAM_NAME} -e rate_limit             # Only rate limit events"
      puts "  #{$PROGRAM_NAME} -k api                    # Only events for keys containing 'api'"
      puts "  #{$PROGRAM_NAME} --json                    # JSON output"
      puts "  #{$PROGRAM_NAME} /path/to/custom.log       # Analyze custom log file"
      exit
    end
  end.parse!

  log_file = ARGV[0]
  analyzer = InstrumentationLogAnalyzer.new(log_file, options)
  analyzer.analyze!
end
