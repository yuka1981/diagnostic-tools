# frozen_string_literal: true

require "net/ssh"
require "net/scp"

module Agent
  class RemoteInstallService
    class InstallError < StandardError; end

    BASTION_TMP_PATH = "/tmp/agent_bin"
    TARGET_BIN_PATH = "/usr/local/bin/hpc-agent"

    def initialize(target_host:, arch:, bastion_user: nil, bastion_host: nil, bastion_password: nil, sudo_password:, local_binary_path:, server_url: nil, agent_token: nil, node: nil, on_progress: nil)
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
      @node = node
      @on_progress = on_progress
    end

    def call
      report_progress "Starting remote installation on #{@target_host}"
      if use_bastion?
        install_via_bastion
      else
        install_direct
      end
    end

    private

    def use_bastion?
      return false if localhost?
      @bastion_host.present?
    end

    def localhost?
      @target_host == "127.0.0.1" || @target_host == "localhost" || @target_host == "::1"
    end

    def install_via_bastion
      # Fallback to sudo_password if bastion_password is blank
      effective_password = @bastion_password.presence || @sudo_password
      ssh_options = default_ssh_options.merge(password: effective_password).compact

      Rails.logger.debug "[RemoteInstallService] Connecting to bastion: #{@bastion_user}@#{@bastion_host}"
      Net::SSH.start(@bastion_host, @bastion_user, ssh_options) do |ssh|
        # Phase 1: Upload to Bastion
        report_progress "Uploading binary to bastion host (#{@bastion_host})"
        ssh.scp.upload!(@local_binary_path, BASTION_TMP_PATH)

        # Phase 2: Bastion to Target
        report_progress "Transferring binary to target node (#{@target_host})"
        Rails.logger.info "Transferring binary from bastion to target: #{@target_host}"
        target_spec = @target_host.include?(":") ? "[#{@target_host}]" : @target_host
        # sudo is executed on the bastion host for scp
        scp_cmd = "sudo -S scp -o StrictHostKeyChecking=no #{BASTION_TMP_PATH} #{target_user}@#{Shellwords.escape(target_spec)}:#{TARGET_BIN_PATH}"
        execute_remote_command(ssh, scp_cmd, password: @sudo_password)

        # Phase 3: Remote Config on Target
        configure_target(ssh, via_ssh: true)
      end
      true
    rescue => e
      Rails.logger.error "Remote install via bastion failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise InstallError, "Installation failed: #{e.message}"
    end

    def install_direct
      # Fallback to sudo_password if bastion_password is blank
      effective_password = @bastion_password.presence || @sudo_password
      ssh_options = default_ssh_options.merge(password: effective_password).compact
      # For consistency with the user requirement, try root first if no explicit bastion_user provided
      user = @bastion_user.presence || "root"

      connect_host = ssh_target_host

      begin
        Rails.logger.debug "[RemoteInstallService] Connecting directly to target: #{user}@#{connect_host}"
        Net::SSH.start(connect_host, user, ssh_options) do |ssh|
          perform_direct_install(ssh, connect_host)
        end
      rescue Net::SSH::ConnectionTimeout, Errno::ETIMEDOUT, Errno::EHOSTUNREACH => e
        # If we used IP and failed, try hostname if it's different
        if connect_host == @node&.ip && @target_host != @node&.ip
          Rails.logger.warn "[RemoteInstallService] Connection to IP #{connect_host} failed: #{e.message}. Retrying with hostname: #{@target_host}"
          report_progress "Connection to IP failed. Retrying with hostname #{@target_host}..."

          connect_host = @target_host
          retry
        end
        raise e
      end

      true
    rescue => e
      Rails.logger.error "Direct remote install failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise InstallError, "Installation failed: #{e.message}"
    end

    def perform_direct_install(ssh, host_display)
      # Phase 1: Upload directly to target
      report_progress "Uploading binary directly to target host (#{host_display})"
      # Upload to /tmp first as we might not have permission for /usr/local/bin yet
      ssh.scp.upload!(@local_binary_path, "/tmp/agent_bin_install")

      # Move to final location using sudo
      report_progress "Moving binary to #{TARGET_BIN_PATH}"
      mv_cmd = "sudo -S mv /tmp/agent_bin_install #{TARGET_BIN_PATH}"
      execute_remote_command(ssh, mv_cmd, password: @sudo_password)

      # Phase 2: Config
      configure_target(ssh, via_ssh: false)
    end

    private

    def ssh_target_host
      @node&.ip.present? ? @node.ip : @target_host
    end

    def target_user
      "root"
    end

    def default_ssh_options
      {
        timeout: 15,
        non_interactive: true,
        verify_host_key: :never,
        append_all_supported_algorithms: true,
        auth_methods: [ "password", "keyboard-interactive" ]
      }
    end

    def bash_c_command(cmd)
      # Wrap command in single quotes for bash -c, escaping existing single quotes
      # This ensures the command string is passed as a single argument to bash
      quoted_cmd = "'" + cmd.gsub("'", "'\\\\''") + "'"
      "bash -c #{quoted_cmd}"
    end

    def configure_target(ssh, via_ssh: false)
      report_progress "Configuring agent service on target"



          # 3.1: chmod +x

          inner_chmod = "chmod +x #{TARGET_BIN_PATH}"



                          chmod_cmd = if via_ssh



                                        "sudo -S ssh -o StrictHostKeyChecking=no #{target_user}@#{Shellwords.escape(@target_host)} #{Shellwords.escape(inner_chmod)}"



                          else



                                        "sudo -S #{inner_chmod}"



                          end







          execute_remote_command(ssh, chmod_cmd, password: @sudo_password)



          # 3.2: Create systemd service

          service_content = <<~SERVICE

            [Unit]

            Description=HPC Diagnostic Agent

            After=network.target



            [Service]

            ExecStart=#{TARGET_BIN_PATH} inventory push --server "#{@server_url}" --token "#{@agent_token}"

            Restart=always

            User=root



            [Install]

            WantedBy=multi-user.target

          SERVICE



          service_file_path = "/etc/systemd/system/hpc-agent.service"

          tmp_service_path = "/tmp/hpc-agent.service"



          # Write content to temp file on the current session (bastion or target)

          # We use a simple heredoc. Shellwords.escape isn't ideal for whole files,

          # but we trust our own service_content.

          ssh.exec!("cat << 'EOF' > #{tmp_service_path}\n#{service_content}EOF")



                if via_ssh



                  # Transfer from bastion to target



                  # sudo is on bastion side



                  transfer_service_cmd = "sudo -S scp -o StrictHostKeyChecking=no #{tmp_service_path} #{target_user}@#{Shellwords.escape(@target_host)}:#{service_file_path}"



                  execute_remote_command(ssh, transfer_service_cmd, password: @sudo_password)



                else





            # Move directly on target

            mv_service_cmd = "sudo -S mv #{tmp_service_path} #{service_file_path}"

            execute_remote_command(ssh, mv_service_cmd, password: @sudo_password)

                end



      # 3.2.5 Ensure ownership is root:root
      report_progress "Setting file ownership to root:root"
      inner_chown = "chown root:root #{TARGET_BIN_PATH} #{service_file_path}"
      chown_cmd = if via_ssh
                    remote_cmd = bash_c_command(inner_chown)
                    "sudo -S ssh -o StrictHostKeyChecking=no #{target_user}@#{Shellwords.escape(@target_host)} #{Shellwords.escape(remote_cmd)}"
      else
                    "sudo -S #{bash_c_command(inner_chown)}"
      end
      execute_remote_command(ssh, chown_cmd, password: @sudo_password)



      # 3.3: systemctl enable --now
      report_progress "Starting agent service"

      inner_systemd = "systemctl daemon-reload && systemctl enable --now hpc-agent"
      systemd_cmd = if via_ssh
                      remote_cmd = bash_c_command(inner_systemd)
                      "sudo -S ssh -o StrictHostKeyChecking=no #{target_user}@#{Shellwords.escape(@target_host)} #{Shellwords.escape(remote_cmd)}"
      else
                      "sudo -S #{bash_c_command(inner_systemd)}"
      end







          execute_remote_command(ssh, systemd_cmd, password: @sudo_password)



      # 3.4: dmidecode SUID
      report_progress "Ensuring dmidecode has SUID permission (4755)"
      inner_dmi = "which dmidecode && chmod 4755 $(which dmidecode)"
      dmi_cmd = if via_ssh
                  remote_cmd = bash_c_command(inner_dmi)
                  "sudo -S ssh -o StrictHostKeyChecking=no #{target_user}@#{Shellwords.escape(@target_host)} #{Shellwords.escape(remote_cmd)}"
      else
                  "sudo -S #{bash_c_command(inner_dmi)}"
      end





          execute_remote_command(ssh, dmi_cmd, password: @sudo_password)
        end



    def report_progress(message)
      @on_progress&.call(message)

      # Also stream step description to terminal for transparency
      report_log("==> #{message}", "meta")
    end

    def validate_target_host!
      # Basic validation for hostname or IP address (including IPv6 colons)
      unless @target_host =~ /\A[a-zA-Z0-9.:-]+\z/
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

          channel.on_data do |_c, data|
            stdout += data
            report_log(data, "stdout")
          end
          channel.on_extended_data do |_c, _type, data|
            stderr += data
            report_log(data, "stderr")
            # Force newline after sudo prompt so subsequent output starts on a new line
            if data.match?(/\[sudo\] password for .*: /)
              report_log("\n", "stderr")
            end
          end
          channel.on_request("exit-status") { |_c, data| exit_code = data.read_long }
        end
      end
      ssh.loop

      Rails.logger.debug "[RemoteInstallService] Exit code: #{exit_code}"
      Rails.logger.debug "[RemoteInstallService] Stdout: #{stdout}" if stdout.present?
      Rails.logger.debug "[RemoteInstallService] Stderr: #{stderr}" if stderr.present?

      if exit_code != 0
        # Filter out the sudo password prompt if it exists in stderr
        clean_stderr = stderr.gsub(/\[sudo\] password for .*: /, "").strip
        # Log the full error context
        Rails.logger.error "[RemoteInstallService] Command failed: #{cmd}"
        Rails.logger.error "[RemoteInstallService] Error output: #{clean_stderr}"

        raise InstallError, "Command failed with exit code #{exit_code}. Error: #{clean_stderr}"
      end

      stdout
    end

    def report_log(data, stream)
      return unless @node

      ActionCable.server.broadcast("node_logs_#{@node.id}", { log: data, stream: stream })
    end
  end
end
