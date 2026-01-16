# frozen_string_literal: true

module Agent
  class UpdateJob < ApplicationJob
    queue_as :default

    def perform(node:, agent_release:, force: false, credentials_cache_key: nil)
      Rails.logger.debug "[Agent::UpdateJob] Starting update for #{node.hostname} to #{agent_release.version}"

      # Retrieve sudo credentials from cache if provided
      sudo_password = nil
      if credentials_cache_key.present?
        credentials = Rails.cache.read("update_creds_#{credentials_cache_key}")
        sudo_password = credentials&.dig(:sudo_password)
        # Clean up credentials from cache
        Rails.cache.delete("update_creds_#{credentials_cache_key}")
      end

      # Fall back to node's stored sudo credential
      sudo_password ||= node.sudo_credential

      # Small delay to allow the browser to establish ActionCable connection
      sleep 0.5 if Rails.env.development?

      broadcast_status(node, "processing", "Starting agent update to #{agent_release.version}")

      # Store original sudo_credential and temporarily set the one from credentials
      original_sudo_credential = node.sudo_credential
      node.sudo_credential = sudo_password if sudo_password.present?

      begin
        service = Agent::PatchService.new(
          node: node,
          agent_release: agent_release,
          force: force,
          on_progress: ->(msg) {
            Rails.logger.debug "[Agent::UpdateJob] Progress: #{msg}"
            broadcast_status(node, "processing", msg)
          }
        )

        result = service.call

        Rails.logger.info "[Agent::UpdateJob] Update successful for #{node.hostname}"
        broadcast_status(node, "success", result.message)
      ensure
        # Restore original sudo_credential
        node.sudo_credential = original_sudo_credential
      end
    rescue Agent::NodeBusyError => e
      Rails.logger.warn "[Agent::UpdateJob] Node busy: #{node.hostname}"
      broadcast_status(node, "error", "Node is busy with pending/running tasks. Use force option to override.")
    rescue Agent::PatchService::PatchError => e
      Rails.logger.error "[Agent::UpdateJob] Update failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      broadcast_status(node, "error", e.message)
    rescue => e
      Rails.logger.error "[Agent::UpdateJob] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      broadcast_status(node, "error", "Unexpected error: #{e.message}")
    end

    private

    def broadcast_status(node, status, message)
      Turbo::StreamsChannel.broadcast_replace_to(
        "agent_update_#{node.id}",
        target: "agent_update_status_#{node.id}",
        partial: "nodes/updates/status",
        locals: { status: status, message: message, node: node }
      )
    end
  end
end
