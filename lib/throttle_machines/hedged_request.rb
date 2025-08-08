# frozen_string_literal: true

require 'concurrent-ruby'

module ThrottleMachines
  # Hedged Request - Multi-path Navigation System
  #
  # Like sending scout ships on multiple routes to find the fastest path.
  # The first ship to reach the destination wins, others are recalled.
  #
  # Reduces latency by racing multiple backends/attempts with staggered delays.
  #
  # Example:
  #   hedged = ThrottleMachines::HedgedRequest.new(
  #     delay: 0.05,     # 50ms between attempts
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

    def initialize(delay: 0.05, max_attempts: 2, timeout: nil)
      @delay = delay
      @max_attempts = max_attempts
      @timeout = timeout
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: max_attempts,
        max_queue: max_attempts,
        fallback_policy: :caller_runs
      )
    end

    # Run hedged request with automatic cancellation of slower attempts
    def run(&block)
      raise ArgumentError, 'Block required' unless block

      # Generate a unique request ID for tracking
      request_id = "#{object_id}-#{Time.now.to_f}"

      # Instrument the start of the hedged request
      Instrumentation.hedged_request_started(request_id, attempts: @max_attempts)

      # Use Concurrent::Promises for better async handling
      futures = []
      first_result = Concurrent::Promises.resolvable_future
      start_time = Time.now.to_f

      @max_attempts.times do |attempt|
        # Schedule with delay
        future = if attempt.zero?
                   Concurrent::Promises.future { yield(attempt) }
                 else
                   Concurrent::Promises.schedule(@delay * attempt) { yield(attempt) }
                 end

        # Race to resolve first_result
        future.then do |result|
          if !first_result.resolved? && first_result.fulfill(result)
            # This attempt won the race
            duration = Time.now.to_f - start_time
            Instrumentation.hedged_request_winner(request_id, attempt: attempt, duration: duration)
          end
          result
        end.rescue do |error|
          # Only reject if this was the last attempt and nothing succeeded
          first_result.reject(error) if attempt == @max_attempts - 1 && !first_result.resolved?
        end

        futures << future
      end

      # Wait with optional timeout
      if @timeout
        # Use any_resolved_future with timeout
        timeout_future = Concurrent::Promises.schedule(@timeout) do
          raise TimeoutError, "Hedged request timed out after #{@timeout}s"
        end

        Concurrent::Promises.any_resolved_future(first_result, timeout_future).value!
      else
        first_result.value!
      end
    ensure
      # Cancel pending futures
      futures.each { |f| f.cancel if f.pending? }
    end

    # Run async version
    def run_async(&)
      Concurrent::Promises.future { run(&) }
    end

    # Shutdown the executor
    def shutdown
      @executor.shutdown
      @executor.wait_for_termination(5)
    end
  end

  # Convenience method
  def self.hedged_request(**, &)
    hedged = HedgedRequest.new(**)
    begin
      hedged.run(&)
    ensure
      hedged.shutdown
    end
  end
end
