# frozen_string_literal: true

module Agent
  class UninstallJob < ApplicationJob
    queue_as :default

    def perform(target_host:, bastion_host: nil, bastion_user:, credentials_cache_key:)
      Rails.logger.debug "[Agent::UninstallJob] Starting uninstall for #{target_host}"

      # Retrieve sensitive credentials from cache
      credentials = Rails.cache.read("install_creds_#{credentials_cache_key}")
      unless credentials
        Rails.logger.error "[Agent::UninstallJob] Credentials not found in cache for key: #{credentials_cache_key}"
        raise "Uninstallation failed: Credentials expired or not found. Please try again."
      end

      # Ensure credentials are cleaned up
      Rails.cache.delete("install_creds_#{credentials_cache_key}")

      # Find node record early
      node = Node.find_by(hostname: target_host)

      # Small delay to allow the browser to establish ActionCable connection
      sleep 1 if Rails.env.development?

      # 1. Remote Uninstall
      # Initial broadcast to show the list
      broadcast_status(target_host, "processing", "Starting uninstallation...", nil)

      uninstaller = Agent::RemoteUninstallService.new(
        target_host: target_host,
        bastion_host: bastion_host,
        bastion_user: bastion_user,
        bastion_password: credentials[:bastion_password],
        sudo_password: credentials[:sudo_password],
        node: node,
        on_progress: ->(step, msg) {
          Rails.logger.debug "[Agent::UninstallJob] Step: #{step} - #{msg}"
          broadcast_status(target_host, "processing", msg, step)
        }
      )

      uninstaller.call

      # 2. Update Node Record
      Rails.logger.debug "[Agent::UninstallJob] Updating Node record for #{target_host}"
      # We don't delete the node, just mark it as possibly offline or handled manually now.
      # For now, we'll just log it. Maybe in future we update source to manual.

      if node
        node.update(source: :manual, agent_version: nil)
      end

      # 3. Success Broadcast
      Rails.logger.debug "[Agent::UninstallJob] Uninstallation Successful"
      broadcast_status(target_host, "success", "Agent uninstalled successfully", :done)
    rescue => e
      Rails.logger.error "[Agent::UninstallJob] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      broadcast_status(target_host, "error", e.message, nil)
    end

    private

    def broadcast_status(target_host, status, message, step)
      Turbo::StreamsChannel.broadcast_replace_to(
        "agent_uninstall_#{target_host.parameterize}",
        target: "agent_uninstall_status_#{target_host.parameterize}",
        partial: "nodes/uninstalls/status",
        locals: {
          status: status,
          message: message,
          target_host: target_host,
          current_step: step,
          steps: Agent::RemoteUninstallService::STEPS
        }
      )
    end
  end
end
