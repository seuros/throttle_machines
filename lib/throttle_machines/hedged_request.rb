# frozen_string_literal: true

require 'concurrent-ruby'

module ThrottleMachines
  # Hedged Request - Multi-path Navigation System
  #
  # Like sending scout ships on multiple routes to find the fastest path.
  # The first ship to reach the destination wins, others are recalled.
  #
  # Reduces latency by racing attempts started `delay` apart. `delay` and
  # `timeout` are Integer nanoseconds (`timeout` nil for none).
  #
  # Example:
  #   hedged = ThrottleMachines::HedgedRequest.new(
  #     delay: 50_000_000, # 50 ms between attempts
  #     max_attempts: 3
  #   )
  #
  #   result = hedged.run do |attempt|
  #     case attempt
  #     when 0 then primary_backend.get(key)
  #     when 1 then secondary_backend.get(key)
  #     when 2 then tertiary_backend.get(key)
  #     end
  #   end
  class HedgedRequest
    attr_reader :delay, :max_attempts, :timeout

    def initialize(delay: 50_000_000, max_attempts: 2, timeout: nil)
      @delay = span(delay, 'delay')
      @max_attempts = max_attempts
      @timeout = timeout.nil? ? nil : span(timeout, 'timeout')
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: max_attempts,
        max_queue: max_attempts,
        fallback_policy: :caller_runs
      )
    end

    # Run hedged request with automatic cancellation of slower attempts
    def run
      raise ArgumentError, 'Block required' unless block_given?

      start_time = ThrottleMachines.monotonic_time
      request_id = "#{object_id}-#{start_time}"
      Instrumentation.hedged_request_started(request_id, attempts: @max_attempts)

      first_result = Concurrent::Promises.resolvable_future

      @max_attempts.times do |attempt|
        future = if attempt.zero?
                   Concurrent::Promises.future_on(@executor) { yield(attempt) }
                 else
                   Concurrent::Promises.schedule_on(@executor, seconds(@delay * attempt)) { yield(attempt) }
                 end

        future.then do |result|
          if !first_result.resolved? && first_result.fulfill(result)
            duration = ThrottleMachines.monotonic_time - start_time
            Instrumentation.hedged_request_winner(request_id, attempt: attempt, duration: duration)
          end
          result
        end.rescue do |error|
          # Only reject if this was the last attempt and nothing succeeded
          first_result.reject(error) if attempt == @max_attempts - 1 && !first_result.resolved?
        end
      end

      return first_result.value! unless @timeout

      timeout_future = Concurrent::Promises.schedule(seconds(@timeout)) do
        raise Timeout::Error, "Hedged request timed out after #{@timeout} ns"
      end
      Concurrent::Promises.any_resolved_future(first_result, timeout_future).value!
    end

    def run_async(&)
      Concurrent::Promises.future { run(&) }
    end

    def shutdown
      @executor.shutdown
      @executor.wait_for_termination(5)
    end

    private

    def span(value, name)
      raise TypeError, "#{name} must be an Integer, got #{value.inspect}" unless value.is_a?(Integer)
      raise RangeError, "#{name} must not be negative, got #{value}" if value.negative?

      value
    end

    def seconds(nanoseconds)
      Rational(nanoseconds, NS_PER_SECOND)
    end
  end
end
