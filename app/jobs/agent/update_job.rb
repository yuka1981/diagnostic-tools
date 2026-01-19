# frozen_string_literal: true

module Agent
  class UpdateJob < ApplicationJob
    queue_as :default

    def perform(node:, agent_release:, force: false, credentials_cache_key: nil)
      Rails.logger.debug "[Agent::UpdateJob] Starting update for #{node.hostname} to #{agent_release.version}"

      # Prepare lifecycle credentials cache key
      lifecycle_cache_key = nil

      if credentials_cache_key.present?
        # Retrieve credentials from cache
        credentials = Rails.cache.read("update_creds_#{credentials_cache_key}")
        Rails.cache.delete("update_creds_#{credentials_cache_key}")

        if credentials.present?
          # Store in format expected by LifecycleService
          lifecycle_cache_key = "lifecycle_creds_#{credentials_cache_key}"
          Rails.cache.write(lifecycle_cache_key, {
            ssh_password: credentials[:ssh_password],
            sudo_password: credentials[:sudo_password]
          }, expires_in: 10.minutes)
        end
      end

      # Small delay to allow the browser to establish ActionCable connection
      sleep 0.5 if Rails.env.development?

      broadcast_status(node, "processing", "Starting agent update to #{agent_release.version}")

      service = Agent::UpdateService.new(
        node: node,
        agent_release: agent_release,
        force: force,
        cache_key: lifecycle_cache_key,
        on_progress: ->(msg) {
          Rails.logger.debug "[Agent::UpdateJob] Progress: #{msg}"
          broadcast_status(node, "processing", msg)
        }
      )

      result = service.call

      Rails.logger.info "[Agent::UpdateJob] Update successful for #{node.hostname}"
      broadcast_status(node, "success", result.message)
    rescue Agent::Errors::NodeBusyError => e
      Rails.logger.warn "[Agent::UpdateJob] Node busy: #{node.hostname}"
      broadcast_status(node, "error", "Node is busy with pending/running tasks. Use force option to override.")
    rescue Agent::Errors::LifecycleError => e
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
