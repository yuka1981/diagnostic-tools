# frozen_string_literal: true

require "resolv"

module Agent
  class InstallJob < ApplicationJob
    queue_as :default

    def perform(node:, target_host:, arch:, bastion_host: nil, bastion_user:, credentials_cache_key:, server_url:, api_key_id: nil)
      Rails.logger.debug "[Agent::InstallJob] Starting install for #{target_host} (arch: #{arch})"

      # Retrieve sensitive credentials from cache
      credentials = Rails.cache.read("install_creds_#{credentials_cache_key}")
      unless credentials
        Rails.logger.error "[Agent::InstallJob] Credentials not found in cache for key: #{credentials_cache_key}"
        raise "Installation failed: Credentials expired or not found. Please try again."
      end

      # Ensure credentials are cleaned up
      Rails.cache.delete("install_creds_#{credentials_cache_key}")

      # Fetch API token if api_key_id is provided
      agent_token = if api_key_id
        ApiKey.active.find_by(id: api_key_id)&.token
      else
        credentials[:agent_token]
      end

      # Small delay to allow the browser to establish ActionCable connection
      sleep 1 if Rails.env.development?

      # 1. Compile Agent
      Rails.logger.debug "[Agent::InstallJob] Phase 1: Compiling"
      broadcast_status(target_host, "processing", "Compiling Go agent for #{arch}")
      compiler = Agent::CompilerService.new(arch)
      local_binary_path = compiler.call

      # 2. Remote Install
      Rails.logger.debug "[Agent::InstallJob] Phase 2: Remote Installation"
      installer = Agent::RemoteInstallService.new(
        target_host: target_host,
        arch: arch,
        bastion_host: bastion_host,
        bastion_user: bastion_user,
        bastion_password: credentials[:bastion_password],
        sudo_password: credentials[:sudo_password],
        local_binary_path: local_binary_path,
        server_url: server_url,
        agent_token: agent_token, # Use the selected token if available
        node: node,
        on_progress: ->(msg) {
          Rails.logger.debug "[Agent::InstallJob] Progress: #{msg}"
          broadcast_status(target_host, "processing", msg)
        }
      )

      installer.call

      # 3. Success Broadcast
      Rails.logger.debug "[Agent::InstallJob] Installation Successful"
      broadcast_status(target_host, "success", "Agent installed successfully")
    rescue => e
      Rails.logger.error "[Agent::InstallJob] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      broadcast_status(target_host, "error", e.message)
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
