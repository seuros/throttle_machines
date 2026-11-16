# frozen_string_literal: true

module ThrottleMachines
  # Rails controller helpers. `period:` is Integer nanoseconds; responses
  # report waits in whole seconds, rounded up.
  module ControllerHelpers
    extend ActiveSupport::Concern

    included do
      if respond_to?(:helper_method) # No available in API Mode
        helper_method :rate_limited?
        helper_method :rate_limit_remaining
      end
    end

    def throttle!(key = nil, limit:, period:, algorithm: :gcra)
      key ||= default_throttle_key

      limiter = ThrottleMachines.limiter(key, limit: limit, period: period, algorithm: algorithm)
      limiter.throttle!
      set_rate_limit_headers(limiter)
    rescue ThrottledError
      render_rate_limited(limiter)
    end

    def with_throttle(key = nil, limit:, period:, &block)
      key ||= default_throttle_key

      ThrottleMachines.limit(key, limit: limit, period: period, &block)
    rescue ThrottledError => e
      render_rate_limited(e.limiter)
    end

    def rate_limited?(key = nil, limit:, period:)
      key ||= default_throttle_key
      limiter = ThrottleMachines.limiter(key, limit: limit, period: period)
      !limiter.allow?
    end

    def rate_limit_remaining(key = nil, limit:, period:)
      key ||= default_throttle_key
      limiter = ThrottleMachines.limiter(key, limit: limit, period: period)
      limiter.remaining
    end

    private

    def default_throttle_key
      if current_user.respond_to?(:id)
        "user:#{current_user.id}"
      else
        "ip:#{request.remote_ip}"
      end
    end

    def render_rate_limited(limiter)
      set_rate_limit_headers(limiter)
      wait = limiter.retry_after.ceildiv(NS_PER_SECOND)

      respond_to do |format|
        format.json do
          render json: { error: 'Rate limit exceeded', retry_after: wait }, status: :too_many_requests
        end

        format.html do
          render plain: "Rate limit exceeded. Please try again in #{wait} seconds.",
                 status: :too_many_requests
        end
      end
    end

    def set_rate_limit_headers(limiter)
      wait = limiter.retry_after.ceildiv(NS_PER_SECOND)
      response.headers['X-RateLimit-Limit'] = limiter.limit.to_s
      response.headers['X-RateLimit-Remaining'] = limiter.remaining.to_s
      response.headers['X-RateLimit-Reset'] = (Time.now.to_i + wait).to_s
      response.headers['Retry-After'] = wait.to_s
    end
  end
end
