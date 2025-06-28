# frozen_string_literal: true

class HealthController < ApplicationController
  def show
    health_status = {
      status: 'ok',
      timestamp: Time.current,
      services: check_services
    }

    render json: health_status
  end

  private

  def check_services
    {
      circuits: check_circuits,
      rate_limits: check_rate_limits
    }
  end

  def check_circuits
    # ThrottleMachines doesn't have a global registry like BreakerMachines
    # Return a simple status
    'circuits operational'
  end

  def check_rate_limits
    # Check if middleware is enabled
    if ThrottleMachines::RackMiddleware.enabled
      'rate limiting enabled'
    else
      'rate limiting disabled'
    end
  end
end
