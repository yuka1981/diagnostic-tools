# frozen_string_literal: true

require "net/ssh"
require "net/scp"

module Agent
  class RemoteInstallService
    class InstallError < StandardError; end

    BASTION_TMP_PATH = "/tmp/agent_bin"
    TARGET_BIN_PATH = "/usr/local/bin/agent"

    def initialize(target_host:, arch:, bastion_user: nil, bastion_host: nil, bastion_password: nil, sudo_password:, local_binary_path:, server_url: nil, agent_token: nil, on_progress: nil)
      @target_host = target_host
      validate_target_host!

      @arch = arch
      @bastion_host = bastion_host.presence
      @bastion_user = bastion_user.presence || "root"
      @bastion_password = bastion_password
      @sudo_password = sudo_password
      @local_binary_path = local_binary_path
      @server_url = server_url || ENV.fetch("APP_URL", "http://localhost:3000")
      @agent_token = agent_token || Rails.application.credentials.dig(:api, :agent_token) || ENV["AGENT_TOKEN"]
      @on_progress = on_progress
    end

    def call
      if @bastion_host.present?
        install_via_bastion
      else
        install_direct
      end
    end

    private

    def install_via_bastion
      ssh_options = { password: @bastion_password }.compact

      Net::SSH.start(@bastion_host, @bastion_user, ssh_options) do |ssh|
        # Phase 1: Upload to Bastion
        report_progress "Uploading binary to bastion host (#{@bastion_host})"
        ssh.scp.upload!(@local_binary_path, BASTION_TMP_PATH)

        # Phase 2: Bastion to Target
        report_progress "Transferring binary to target node (#{@target_host})"
        Rails.logger.info "Transferring binary from bastion to target: #{@target_host}"
        scp_cmd = "sudo -S scp -o StrictHostKeyChecking=no #{BASTION_TMP_PATH} root@#{Shellwords.escape(@target_host)}:#{TARGET_BIN_PATH}"
        execute_remote_command(ssh, scp_cmd, password: @sudo_password)

        # Phase 3: Remote Config on Target
        configure_target(ssh, via_ssh: true)
      end
      true
    rescue => e
      Rails.logger.error "Remote install via bastion failed: #{e.message}"
      raise InstallError, "Installation failed: #{e.message}"
    end

    def install_direct
      ssh_options = { password: @bastion_password }.compact
      target_user = @bastion_user # Use the provided user for direct connection

      Net::SSH.start(@target_host, target_user, ssh_options) do |ssh|
        # Phase 1: Upload directly to target
        report_progress "Uploading binary directly to target host (#{@target_host})"
        # Upload to /tmp first as we might not have permission for /usr/local/bin yet
        ssh.scp.upload!(@local_binary_path, "/tmp/agent_bin_install")

        # Move to final location using sudo
        report_progress "Moving binary to #{TARGET_BIN_PATH}"
        mv_cmd = "sudo -S mv /tmp/agent_bin_install #{TARGET_BIN_PATH}"
        execute_remote_command(ssh, mv_cmd, password: @sudo_password)

        # Phase 2: Config
        configure_target(ssh, via_ssh: false)
      end
      true
    rescue => e
      Rails.logger.error "Direct remote install failed: #{e.message}"
      raise InstallError, "Installation failed: #{e.message}"
    end

    def configure_target(ssh, via_ssh: false)
      report_progress "Configuring agent service on target"

      # Prefix for commands if we are going through bastion via SSH to target
      # If direct, we run commands on the current session
      ssh_prefix = if via_ssh
                     "sudo -S ssh -o StrictHostKeyChecking=no root@#{Shellwords.escape(@target_host)} "
      else
                     "sudo -S "
      end

      # 3.1: chmod +x
      chmod_cmd = "#{ssh_prefix}'chmod +x #{TARGET_BIN_PATH}'"
      execute_remote_command(ssh, chmod_cmd, password: @sudo_password)

      # 3.2: Create systemd service
      service_content = <<~SERVICE
        [Unit]
        Description=HPC Diagnostic Agent
        After=network.target

        [Service]
        ExecStart=#{TARGET_BIN_PATH} push --server "#{@server_url}" --token "#{@agent_token}"
        Restart=always
        User=root

        [Install]
        WantedBy=multi-user.target
      SERVICE

      service_file_path = "/etc/systemd/system/hpc-agent.service"

      if via_ssh
        # Write content to temp file on bastion, then SCP to target
        ssh.exec!("cat << 'EOF' > /tmp/hpc-agent.service\n#{service_content}\nEOF")
        transfer_service_cmd = "sudo -S scp -o StrictHostKeyChecking=no /tmp/hpc-agent.service root@#{Shellwords.escape(@target_host)}:#{service_file_path}"
        execute_remote_command(ssh, transfer_service_cmd, password: @sudo_password)
      else
        # Write directly to target via a temp file
        ssh.exec!("cat << 'EOF' > /tmp/hpc-agent.service\n#{service_content}\nEOF")
        mv_service_cmd = "sudo -S mv /tmp/hpc-agent.service #{service_file_path}"
        execute_remote_command(ssh, mv_service_cmd, password: @sudo_password)
      end

      # 3.3: systemctl enable --now
      report_progress "Starting agent service"
      systemd_cmd = "#{ssh_prefix}'systemctl daemon-reload && systemctl enable --now hpc-agent'"
      execute_remote_command(ssh, systemd_cmd, password: @sudo_password)
    end

    def report_progress(message)
      @on_progress&.call(message)
    end

    def validate_target_host!
      # Basic validation for hostname or IP address
      unless @target_host =~ /\A[a-zA-Z0-9.-]+\z/
        raise InstallError, "Invalid target host format: #{@target_host}"
      end
    end

    def execute_remote_command(ssh, cmd, password: nil)
      stdout = ""
      stderr = ""
      exit_code = nil

      Rails.logger.debug "[RemoteInstallService] Executing: #{cmd.gsub(password.to_s, '********')}" if password.present?
      Rails.logger.debug "[RemoteInstallService] Executing: #{cmd}" unless password.present?

      ssh.open_channel do |ch|
        ch.exec(cmd) do |channel, success|
          raise InstallError, "Could not execute command: #{cmd}" unless success

          if password.present?
            # Send password to sudo -S
            channel.send_data("#{password}\n")
          end

          channel.on_data { |_c, data| stdout += data }
          channel.on_extended_data { |_c, _type, data| stderr += data }
          channel.on_request("exit-status") { |_c, data| exit_code = data.read_long }
        end
      end
      ssh.loop

      Rails.logger.debug "[RemoteInstallService] Exit code: #{exit_code}"
      Rails.logger.debug "[RemoteInstallService] Stdout: #{stdout}" if stdout.present?
      Rails.logger.debug "[RemoteInstallService] Stderr: #{stderr}" if stderr.present?

      if exit_code != 0
        # Filter out the sudo password prompt if it exists in stderr
        clean_stderr = stderr.gsub(/\\[sudo\\] password for .*: /, "").strip
        raise InstallError, "Command failed with exit code #{exit_code}. Error: #{clean_stderr}"
      end

      stdout
    end
  end
end
