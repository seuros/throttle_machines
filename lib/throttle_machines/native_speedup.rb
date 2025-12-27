# frozen_string_literal: true

# Native speedup for ThrottleMachines using Rust FFI.
#
# This module is automatically loaded when the native extension is available.
# It prepends optimized implementations onto Storage::Memory.
#
# Environment controls:
#   DISABLE_MATRYOSHKA_NATIVE=1       - Disable all matryoshka native extensions
#   DISABLE_THROTTLE_MACHINES_NATIVE=1 - Disable only throttle_machines native
#   DEBUG_MATRYOSHKA=1                 - Log which backend is loaded

return if ENV["DISABLE_MATRYOSHKA_NATIVE"]
return if ENV["DISABLE_THROTTLE_MACHINES_NATIVE"]

begin
  require "throttle_machines_native/throttle_machines_native"

  module ThrottleMachines
    module Storage
      # Native GCRA implementation using Rust.
      module NativeGCRA
        def check_gcra_limit(key, emission_interval, delay_tolerance, ttl)
          with_write_lock(key) do
            now = current_time
            state = @gcra_states[key] || { tat: 0.0 }

            # Rust does the math
            allowed, new_tat, retry_after = ThrottleMachinesNative.gcra_check(
              state[:tat], now, emission_interval, delay_tolerance
            )

            @gcra_states[key] = { tat: new_tat, expires_at: now + ttl } if allowed

            { allowed: allowed, retry_after: retry_after, tat: new_tat }
          end
        end

        def peek_gcra_limit(key, _emission_interval, delay_tolerance)
          with_read_lock(key) do
            now = current_time
            state = @gcra_states[key] || { tat: 0.0 }

            # Rust does the math
            allowed, tat, retry_after = ThrottleMachinesNative.gcra_peek(
              state[:tat], now, delay_tolerance
            )

            { allowed: allowed, retry_after: retry_after, tat: tat }
          end
        end
      end

      # Native Token Bucket implementation using Rust.
      module NativeTokenBucket
        def check_token_bucket(key, capacity, refill_rate, ttl)
          with_write_lock(key) do
            now = current_time
            bucket = @token_buckets[key] || { tokens: capacity, last_refill: now }

            # Rust does the math
            allowed, new_tokens, retry_after = ThrottleMachinesNative.token_bucket_check(
              bucket[:tokens], bucket[:last_refill], now, capacity, refill_rate
            )

            if allowed
              @token_buckets[key] = { tokens: new_tokens, last_refill: now, expires_at: now + ttl }
            end

            { allowed: allowed, retry_after: retry_after, tokens_remaining: new_tokens.floor }
          end
        end

        def peek_token_bucket(key, capacity, refill_rate)
          with_read_lock(key) do
            now = current_time
            bucket = @token_buckets[key] || { tokens: capacity, last_refill: now }

            # Rust does the math
            allowed, tokens, retry_after = ThrottleMachinesNative.token_bucket_peek(
              bucket[:tokens], bucket[:last_refill], now, capacity, refill_rate
            )

            { allowed: allowed, retry_after: retry_after, tokens_remaining: tokens.floor }
          end
        end
      end
    end
  end

  # Prepend native implementations
  ThrottleMachines::Storage::Memory.prepend(ThrottleMachines::Storage::NativeGCRA)
  ThrottleMachines::Storage::Memory.prepend(ThrottleMachines::Storage::NativeTokenBucket)

  warn "[ThrottleMachines] Native speedup loaded" if ENV["DEBUG_MATRYOSHKA"]
rescue LoadError => e
  warn "[ThrottleMachines] Native speedup unavailable: #{e.message}" if ENV["DEBUG_MATRYOSHKA"]
end
