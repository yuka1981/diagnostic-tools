# frozen_string_literal: true

module Salt
  class PresenceCheckService
    def initialize(salt_client: nil)
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      status = @salt_client.run_runner("manage.status")
      up_minions = status["up"] || []
      down_minions = status["down"] || []

      up_minions.each do |hostname|
        Node.where(hostname: hostname).update_all(last_heartbeat_at: Time.current)
      end

      down_minions.each do |hostname|
        Node.where(hostname: hostname).update_all(last_heartbeat_at: nil)
      end

      { up: up_minions.size, down: down_minions.size }
    rescue SaltApiClient::TimeoutError, SaltApiClient::ApiError => e
      Rails.logger.error("Salt presence check failed: #{e.message}")
      { error: e.message }
    end
  end
end
