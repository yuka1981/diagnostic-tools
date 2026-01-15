# frozen_string_literal: true

module Api
  module V1
    class HealthController < BaseController
      # GET /api/v1/health
      # Returns a simple health check response to verify:
      # 1. The server is reachable
      # 2. The authentication token is valid
      def show
        render json: {
          status: "ok",
          timestamp: Time.current.iso8601,
          message: "API is reachable and token is valid"
        }
      end
    end
  end
end
