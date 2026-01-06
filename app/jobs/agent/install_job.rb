# frozen_string_literal: true

module Agent
  class InstallJob < ApplicationJob
    queue_as :default

    def perform(target_host:, arch:, bastion_user:, credentials_cache_key:, server_url:)
      # Retrieve sensitive credentials from cache
      credentials = Rails.cache.read("install_creds_#{credentials_cache_key}")
      unless credentials
        raise "Installation failed: Credentials expired or not found. Please try again."
      end

      # Ensure credentials are cleaned up
      Rails.cache.delete("install_creds_#{credentials_cache_key}")

      # 1. Compile Agent
      compiler = Agent::CompilerService.new(arch)
      local_binary_path = compiler.call

      # 2. Remote Install
      installer = Agent::RemoteInstallService.new(
        target_host: target_host,
        arch: arch,
        bastion_user: bastion_user,
        bastion_password: credentials[:bastion_password],
        sudo_password: credentials[:sudo_password],
        local_binary_path: local_binary_path,
        server_url: server_url
      )

      installer.call

      # 3. Success Broadcast
      broadcast_status(target_host, "success", "Agent installed successfully")
    rescue => e
      Rails.logger.error "Agent installation failed for #{target_host}: #{e.message}"
      broadcast_status(target_host, "error", e.message)
    ensure
      # Cleanup local binary if it was created
      FileUtils.rm_f(local_binary_path) if local_binary_path && File.exist?(local_binary_path)
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
