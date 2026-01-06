# frozen_string_literal: true

require "net/ssh"
require "net/scp"

module Agent
  class RemoteInstallService
    class InstallError < StandardError; end

    BASTION_TMP_PATH = "/tmp/agent_bin"
    TARGET_BIN_PATH = "/usr/local/bin/agent"

    def initialize(target_host:, arch:, bastion_user:, bastion_password: nil, sudo_password:, local_binary_path:, server_url: nil, agent_token: nil)
      @target_host = target_host
      @arch = arch
      @bastion_host = SshConfig.jump_host
      @bastion_user = bastion_user
      @bastion_password = bastion_password
      @sudo_password = sudo_password
      @local_binary_path = local_binary_path
      @server_url = server_url || ENV.fetch("APP_URL", "http://localhost:3000")
      @agent_token = agent_token || Rails.application.credentials.dig(:api, :agent_token) || ENV["AGENT_TOKEN"]
    end

    def call
      raise InstallError, "Bastion host not configured (JUMP_HOST ENV is missing)" unless @bastion_host.present?

      ssh_options = { password: @bastion_password }.compact

      Net::SSH.start(@bastion_host, @bastion_user, ssh_options) do |ssh|
        # Phase 1: Upload to Bastion
        Rails.logger.info "Uploading binary to bastion: #{@bastion_host}"
        ssh.scp.upload!(@local_binary_path, BASTION_TMP_PATH)

        # Phase 2: Bastion to Target
        # Use sudo -S to scp from bastion to target.
        # We assume bastion root has passwordless SSH access to target nodes as per PRD.
        Rails.logger.info "Transferring binary from bastion to target: #{@target_host}"
        scp_cmd = "echo '#{@sudo_password}' | sudo -S scp -o StrictHostKeyChecking=no #{BASTION_TMP_PATH} root@#{@target_host}:#{TARGET_BIN_PATH}"
        execute_remote_command(ssh, scp_cmd)

        # Phase 3: Remote Config on Target
        Rails.logger.info "Configuring agent on target: #{@target_host}"

        # 3.1: chmod +x
        chmod_cmd = "echo '#{@sudo_password}' | sudo -S ssh -o StrictHostKeyChecking=no root@#{@target_host} 'chmod +x #{TARGET_BIN_PATH}'"
        execute_remote_command(ssh, chmod_cmd)

        # 3.2: Create systemd service
        service_content = <<~SERVICE
[Unit]
Description=HPC Diagnostic Agent
After=network.target

[Service]
ExecStart=#{TARGET_BIN_PATH} push --server #{@server_url} --token #{@agent_token}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE

        service_file_path = "/etc/systemd/system/hpc-agent.service"
        # Write content to temp file on bastion
        ssh.exec!("cat << 'EOF' > /tmp/hpc-agent.service\n#{service_content}\nEOF")

        transfer_service_cmd = "echo '#{@sudo_password}' | sudo -S scp -o StrictHostKeyChecking=no /tmp/hpc-agent.service root@#{@target_host}:#{service_file_path}"
        execute_remote_command(ssh, transfer_service_cmd)

        # 3.3: systemctl enable --now
        systemd_cmd = "echo '#{@sudo_password}' | sudo -S ssh -o StrictHostKeyChecking=no root@#{@target_host} 'systemctl daemon-reload && systemctl enable --now hpc-agent'"
        execute_remote_command(ssh, systemd_cmd)
      end

      true
    rescue => e
      Rails.logger.error "Remote install failed: #{e.message}"
      raise InstallError, "Installation failed: #{e.message}"
    end

    private

    def execute_remote_command(ssh, cmd)
      stdout = ""
      stderr = ""
      exit_code = nil

      ssh.open_channel do |ch|
        ch.exec(cmd) do |_path, success|
          raise InstallError, "Could not execute command: #{cmd}" unless success
          ch.on_data { |_c, data| stdout += data }
          ch.on_extended_data { |_c, _type, data| stderr += data }
          ch.on_request("exit-status") { |_c, data| exit_code = data.read_long }
        end
      end
      ssh.loop

      if exit_code != 0
        # Filter out the sudo password prompt if it exists in stderr
        clean_stderr = stderr.gsub(/\[sudo\] password for .*: /, "").strip
        raise InstallError, "Command failed with exit code #{exit_code}. Error: #{clean_stderr}"
      end

      stdout
    end
  end
end
