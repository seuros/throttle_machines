# frozen_string_literal: true

class TestController < ApplicationController
  # Process a payment through circuit breaker
  def payment
    amount = params[:amount]&.to_f || 100.0
    card_token = params[:card_token] || 'test-token'
    result = service.process_payment(amount, card_token)

    render json: result
  end

  # Send notification through circuit breaker
  def notification
    email = params[:email] || 'test@example.com'
    subject = params[:subject] || 'Test Notification'
    body = params[:body] || 'This is a test notification'

    result = service.send_notification(email, subject, body)

    render json: result
  end

  # Get circuit breaker status
  def status
    render json: service.service_status
  end

  # Force circuit to trip for testing
  def trip_payment
    results = []

    # Trigger failures within the circuit to trip it
    5.times do
      service.circuit(:payment_gateway).call do
        raise StandardError, 'Forced failure for testing'
      end
    rescue StandardError => e
      results << { error: e.message, class: e.class.name }
    end

    render json: {
      message: 'Attempted to trip payment circuit',
      results: results,
      circuit_state: service.circuit(:payment_gateway).state
    }
  end

  # Reset circuits
  def reset
    # Reset circuits in ThrottleMachines
    payment_circuit = service.circuit(:payment_gateway)
    email_circuit = service.circuit(:email_service)

    # Reset the breakers
    payment_circuit.reset!
    email_circuit.reset!

    render json: {
      message: 'Circuits reset',
      status: service.service_status
    }
  end

  private

  def service
    @service ||= ExternalApiService.new
  end
end
