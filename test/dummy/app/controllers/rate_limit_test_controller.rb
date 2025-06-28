# frozen_string_literal: true

class RateLimitTestController < ApplicationController
  # Test endpoint for basic rate limiting
  def index
    render json: {
      message: 'Request successful',
      timestamp: Time.current,
      ip: request.ip,
      path: request.path
    }
  end

  # API endpoint with different rate limits
  def api
    render json: {
      message: 'API request successful',
      timestamp: Time.current,
      data: { foo: 'bar' }
    }
  end

  # Endpoint to check rate limit headers
  def status
    render json: {
      message: 'Rate limit status',
      headers: {
        'X-RateLimit-Limit': response.headers['X-RateLimit-Limit'],
        'X-RateLimit-Remaining': response.headers['X-RateLimit-Remaining'],
        'X-RateLimit-Reset': response.headers['X-RateLimit-Reset']
      }
    }
  end
end
