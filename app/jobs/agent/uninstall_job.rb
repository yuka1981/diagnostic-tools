# frozen_string_literal: true

module Agent
  class UninstallJob < ApplicationJob
    queue_as :default

    # Steps for UI progress display (matches old RemoteUninstallService::STEPS)
    STEPS = {
      connect: "Connecting to host",
      stop_service: "Stopping agent service",
      remove_files: "Removing files",
      reload_daemon: "Reloading systemd"
    }.freeze

    # Map progress messages to step keys for UI display
    STEP_PATTERNS = {
      /connecting|connection/i => :connect,
      /stopping/i => :stop_service,
      /removing|disabling|cleanup/i => :remove_files,
      /reload|daemon/i => :reload_daemon
    }.freeze

    def perform(target_host:, bastion_host: nil, bastion_user:, credentials_cache_key:, user_id: nil)
      Rails.logger.debug "[Agent::UninstallJob] Starting uninstall for #{target_host}"
      notification = nil

      # Retrieve sensitive credentials from cache
      credentials = Rails.cache.read("install_creds_#{credentials_cache_key}")
      unless credentials
        Rails.logger.error "[Agent::UninstallJob] Credentials not found in cache for key: #{credentials_cache_key}"
        raise "Uninstallation failed: Credentials expired or not found. Please try again."
      end

      # Ensure credentials are cleaned up
      Rails.cache.delete("install_creds_#{credentials_cache_key}")

      # Store credentials in format expected by LifecycleService
      lifecycle_cache_key = "lifecycle_creds_#{credentials_cache_key}"
      Rails.cache.write(lifecycle_cache_key, {
        ssh_password: credentials[:bastion_password],
        sudo_password: credentials[:sudo_password]
      }, expires_in: 10.minutes)

      # Find node record early
      node = Node.find_by(hostname: target_host)

      unless node
        Rails.logger.error "[Agent::UninstallJob] Node not found for hostname: #{target_host}"
        raise "Uninstallation failed: Node not found."
      end

      # Create notification if user_id is provided
      if user_id.present?
        user = User.find_by(id: user_id)
        if user
          notification = NotificationService.create(
            user: user,
            type: "agent_uninstall",
            title: "Uninstalling agent from #{node.hostname}",
            resource: node
          )
          NotificationService.start(notification)
        end
      end

      # Small delay to allow the browser to establish ActionCable connection
      sleep 1 if Rails.env.development?

      # Initial broadcast to show the list
      broadcast_status(target_host, "processing", "Starting uninstallation...", nil)

      uninstaller = Agent::UninstallService.new(
        node: node,
        cache_key: lifecycle_cache_key,
        on_progress: ->(msg) {
          step = infer_step_from_message(msg)
          Rails.logger.debug "[Agent::UninstallJob] Step: #{step} - #{msg}"
          broadcast_status(target_host, "processing", msg, step)
        }
      )

      uninstaller.call
      # Note: UninstallService updates node.source and node.agent_version internally

      # Success Broadcast
      Rails.logger.debug "[Agent::UninstallJob] Uninstallation Successful"
      broadcast_status(target_host, "success", "Agent uninstalled successfully", :done)
      NotificationService.complete(notification, success: true, message: "Agent uninstalled successfully") if notification
    rescue Agent::Errors::LifecycleError => e
      Rails.logger.error "[Agent::UninstallJob] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      broadcast_status(target_host, "error", e.message, nil)
      NotificationService.complete(notification, success: false, message: e.message) if notification
    rescue => e
      Rails.logger.error "[Agent::UninstallJob] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      broadcast_status(target_host, "error", e.message, nil)
      NotificationService.complete(notification, success: false, message: e.message) if notification
    end

    private

    def infer_step_from_message(message)
      STEP_PATTERNS.each do |pattern, step|
        return step if message.match?(pattern)
      end
      nil
    end

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
          steps: STEPS
        }
      )
    end
  end
end
