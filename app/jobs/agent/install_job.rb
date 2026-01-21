# frozen_string_literal: true

require "resolv"

module Agent
  class InstallJob < ApplicationJob
    queue_as :default

    def perform(node:, target_host:, arch:, bastion_host: nil, bastion_user:, credentials_cache_key:, server_url:, api_key_id: nil, user_id: nil)
      Rails.logger.debug "[Agent::InstallJob] Starting install for #{target_host} (arch: #{arch})"
      local_binary_path = nil
      notification = nil

      # Create notification if user_id is provided
      if user_id.present?
        user = User.find_by(id: user_id)
        if user
          notification = NotificationService.create(
            user: user,
            type: "agent_install",
            title: "Installing agent on #{target_host}",
            resource: node
          )
          NotificationService.start(notification)
        end
      end

      # Retrieve sensitive credentials from cache
      credentials = Rails.cache.read("install_creds_#{credentials_cache_key}")
      unless credentials
        Rails.logger.error "[Agent::InstallJob] Credentials not found in cache for key: #{credentials_cache_key}"
        raise "Installation failed: Credentials expired or not found. Please try again."
      end

      # Ensure credentials are cleaned up
      Rails.cache.delete("install_creds_#{credentials_cache_key}")

      # Store credentials in format expected by LifecycleService
      lifecycle_cache_key = "lifecycle_creds_#{credentials_cache_key}"
      Rails.cache.write(lifecycle_cache_key, {
        ssh_password: credentials[:bastion_password],
        sudo_password: credentials[:sudo_password]
      }, expires_in: 10.minutes)

      # Fetch API token if api_key_id is provided
      agent_token = if api_key_id.present?
        ApiKey.active.find_by(id: api_key_id)&.token
      else
        credentials[:agent_token]
      end

      # Small delay to allow the browser to establish ActionCable connection
      sleep 1 if Rails.env.development?

      # 1. Compile Agent (always pull latest source code)
      Rails.logger.debug "[Agent::InstallJob] Phase 1: Compiling"
      broadcast_status(target_host, "processing", "Compiling Go agent for #{arch}")
      compiler = Agent::CompilerService.new(arch: arch, update_source: true)
      local_binary_path = compiler.call

      # 2. Remote Install
      Rails.logger.debug "[Agent::InstallJob] Phase 2: Remote Installation"
      broadcast_status(target_host, "processing", "Connecting to remote host...")

      installer = Agent::InstallService.new(
        node: node,
        server_url: server_url,
        api_token: agent_token,
        binary_path: local_binary_path,
        cache_key: lifecycle_cache_key,
        on_progress: ->(msg) {
          Rails.logger.debug "[Agent::InstallJob] Progress: #{msg}"
          broadcast_status(target_host, "processing", msg)
        }
      )

      installer.call
      # Note: InstallService updates node.uuid and node.agent_version internally

      # 3. Success Broadcast
      Rails.logger.debug "[Agent::InstallJob] Installation Successful"
      broadcast_status(target_host, "success", "Agent installed successfully")
      NotificationService.complete(notification, success: true, message: "Agent installed successfully") if notification
    rescue Agent::Errors::LifecycleError => e
      Rails.logger.error "[Agent::InstallJob] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")

      # Revert node source to manual so the user can retry
      if node&.persisted?
        Rails.logger.info "[Agent::InstallJob] Reverting node #{target_host} source to manual due to failure"
        node.update(source: :manual)
      end

      broadcast_status(target_host, "error", e.message)
      NotificationService.complete(notification, success: false, message: e.message) if notification
    rescue => e
      Rails.logger.error "[Agent::InstallJob] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")

      # Revert node source to manual so the user can retry
      if node&.persisted?
        Rails.logger.info "[Agent::InstallJob] Reverting node #{target_host} source to manual due to failure"
        node.update(source: :manual)
      end

      broadcast_status(target_host, "error", e.message)
      NotificationService.complete(notification, success: false, message: e.message) if notification
    ensure
      # Cleanup local binary if it was created
      if local_binary_path && File.exist?(local_binary_path)
        Rails.logger.debug "[Agent::InstallJob] Cleaning up temp binary: #{local_binary_path}"
        FileUtils.rm_f(local_binary_path)
      end
    end

    private

    def broadcast_status(target_host, status, message)
      Turbo::StreamsChannel.broadcast_replace_to(
        "agent_install_#{target_host.parameterize}",
        target: "agent_install_status_#{target_host.parameterize}",
        partial: "nodes/installs/status",
        locals: { status: status, message: message, target_host: target_host }
      )
    end
  end
end
