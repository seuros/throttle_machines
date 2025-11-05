# frozen_string_literal: true

module ThrottleMachines
  class Middleware
    def initialize(app, &config_block)
      @app = app
      @rules = []

      instance_eval(&config_block) if config_block
    end

    def call(env)
      request = Rack::Request.new(env)

      @rules.each do |rule|
        next unless rule[:matcher].call(request)

        key = rule[:key_generator].call(request)
        limiter = ThrottleMachines.limiter(
          key,
          limit: rule[:limit],
          period: rule[:period],
          algorithm: rule[:algorithm]
        )

        return rate_limit_response(limiter) unless limiter.allow?
      end

      @app.call(env)
    rescue ThrottledError => e
      rate_limit_response(e.limiter)
    end

    def throttle(path, limit:, period:, by: :ip, algorithm: :gcra)
      @rules << {
        matcher: build_matcher(path),
        key_generator: build_key_generator(by),
        limit: limit,
        period: period,
        algorithm: algorithm
      }
    end

    private

    def build_matcher(path)
      case path
      when String
        ->(request) { request.path == path }
      when Regexp
        ->(request) { request.path =~ path }
      when Proc
        path
      else
        ->(_request) { true }
      end
    end

    def build_key_generator(by)
      case by
      when :ip
        ->(request) { "ip:#{request.ip}" }
      when Symbol
        ->(request) { "#{by}:#{request.env['rack.session']&.dig(by)}" }
      when Proc
        by
      else
        ->(_request) { by.to_s }
      end
    end

    def rate_limit_response(limiter)
      headers = {
        'Content-Type' => 'application/json',
        'X-RateLimit-Limit' => limiter.limit.to_s,
        'X-RateLimit-Remaining' => limiter.remaining.to_s,
        'X-RateLimit-Reset' => (Time.now.to_i + limiter.retry_after).to_s,
        'Retry-After' => limiter.retry_after.ceil.to_s
      }

      body = JSON.generate({
                             error: 'Rate limit exceeded',
                             retry_after: limiter.retry_after
                           })

      [429, headers, [body]]
    end
  end
end
