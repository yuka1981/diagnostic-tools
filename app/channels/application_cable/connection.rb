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

      agent_uuid = request.headers["X-Node-ID"]
      return nil if agent_uuid.blank?

      # First, try to find node by agent's UUID (fingerprint)
      node = Node.find_by(uuid: agent_uuid)
      return node if node

      # If not found, try to find by IP and sync the UUID
      # This handles the case where node was created manually/SSH before agent install
      client_ip = request.ip
      if client_ip.present?
        node = Node.find_by(ip: client_ip)
        if node && node.uuid != agent_uuid
          Rails.logger.info "Syncing node #{node.hostname} UUID from #{node.uuid} to agent fingerprint #{agent_uuid}"
          node.update!(uuid: agent_uuid)
          return node
        end
      end

      nil
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
