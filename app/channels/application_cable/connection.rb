module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_node
    identified_by :current_user

    def connect
      if env["warden"]&.user
        self.current_user = env["warden"].user
      elsif (node = find_verified_node)
        self.current_node = node
      else
        reject_unauthorized_connection
      end
    end

    private

    def find_verified_node
      token = extract_token
      return nil unless valid_token?(token)

      node_id = request.headers["X-Node-ID"]
      Node.find_by(uuid: node_id)
    end

    def extract_token
      # Try Authorization header first
      auth_header = request.headers["Authorization"]
      if auth_header.present?
        match = auth_header.match(/\ABearer\s+(.+)\z/)
        return match&.captures&.first if match
      end

      # Fallback to Query Parameter
      request.params[:token]
    end

    def valid_token?(token)
      return false unless token.present?

      api_key = ApiKey.active.find_by(token: token)
      if api_key
        api_key.touch_last_used
        return true
      end

      expected_token = Rails.application.credentials.dig(:api, :agent_token) || ENV["API_AGENT_TOKEN"]
      return false unless expected_token.present?

      ActiveSupport::SecurityUtils.secure_compare(token, expected_token)
    end
  end
end
