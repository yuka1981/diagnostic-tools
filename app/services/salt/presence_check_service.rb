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

      Node.where(hostname: up_minions).update_all(
        salt_status: Node.salt_statuses[:connected],
        last_seen_at: Time.current
      )

      Node.where(hostname: down_minions)
          .where.not(salt_status: Node.salt_statuses[:unknown])
          .update_all(salt_status: Node.salt_statuses[:disconnected])

      { up: up_minions.size, down: down_minions.size }
    rescue SaltApiClient::TimeoutError, SaltApiClient::ApiError => e
      Rails.logger.error("Salt presence check failed: #{e.message}")
      { error: e.message }
    end
  end
end
