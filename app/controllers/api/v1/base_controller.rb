# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_with_token!

      private

      def authenticate_with_token!
        token = extract_bearer_token
        render_unauthorized unless token.present? && valid_token?(token)
      end

      def extract_bearer_token
        auth_header = request.headers["Authorization"]
        return nil unless auth_header.present?

        # Expect format: "Bearer <token>"
        match = auth_header.match(/\ABearer\s+(.+)\z/)
        match&.captures&.first
      end

      def valid_token?(token)
        api_key = ApiKey.active.find_by(token: token)
        
        if api_key
          api_key.touch_last_used
          return true
        end

        # Fallback to legacy static token for transition
        expected_token = Rails.application.credentials.dig(:api, :agent_token) || ENV["API_AGENT_TOKEN"]
        return false unless expected_token.present?

        ActiveSupport::SecurityUtils.secure_compare(token, expected_token)
      end

      def render_unauthorized
        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def render_bad_request(message)
        render json: { error: message }, status: :bad_request
      end

      def render_not_found(message)
        render json: { error: message }, status: :not_found
      end
    end
  end
end
