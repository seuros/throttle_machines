# frozen_string_literal: true

class CircuitsController < ApplicationController
  def index
    # For ThrottleMachines, we'll show both limiters and breakers
    limiters = []
    breakers = []

    # In a real app, you'd track these in a registry
    # For now, we'll just show a sample response
    render json: {
      limiters: limiters,
      breakers: breakers,
      message: 'ThrottleMachines circuit status'
    }
  end

  def reset
    # In ThrottleMachines, you'd reset a specific breaker
    render json: {
      message: 'Circuit reset functionality for ThrottleMachines',
      name: params[:name]
    }
  end
end
