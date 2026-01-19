# frozen_string_literal: true

require "net/ssh"
require "net/scp"
require "open3"

module Agent
  class RemoteInstallService
    class InstallError < StandardError; end

    # Result object returned after successful installation
    Result = Struct.new(:success, :agent_uuid, keyword_init: true) do
      def success?
        success
      end
    end

    BASTION_TMP_PATH = "/tmp/agent_bin"
    TARGET_BIN_PATH = "/usr/local/bin/hpc-agent"
    AGENT_CONFIG_DIR = "/etc/hpc-agent"
    AGENT_NODE_ID_PATH = "#{AGENT_CONFIG_DIR}/node_id"
    LOCAL_SUDO_TIMEOUT = 30 # seconds - timeout for local sudo commands to prevent hanging

    def initialize(target_host:, arch:, bastion_user: nil, bastion_host: nil, bastion_password: nil, sudo_password:, local_binary_path:, server_url: nil, agent_token: nil, node: nil, on_progress: nil)
      @target_host = target_host
      validate_target_host!

      @arch = arch
      @bastion_host = bastion_host.presence
      @bastion_user = bastion_user.presence || "root"
      @bastion_password = bastion_password
      @sudo_password = sudo_password
      @local_binary_path = local_binary_path
      @server_url = normalize_server_url(server_url || ENV.fetch("APP_URL", "http://localhost:3000"))
      @agent_token = agent_token || Rails.application.credentials.dig(:api, :agent_token) || ENV["AGENT_TOKEN"]
      @node = node
      @on_progress = on_progress
    end

    def call
      ActiveSupport::Deprecation.new.warn(
        "Agent::RemoteInstallService is deprecated. Use Agent::InstallService instead. " \
        "Called from: #{caller_locations(1, 1)&.first}",
        caller_locations
      )

      if localhost?
        report_progress "Starting local installation on #{@target_host}"
        install_local
      elsif use_bastion?
        report_progress "Starting remote installation on #{@target_host}"
        install_via_bastion
      else
        report_progress "Starting remote installation on #{@target_host}"
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

      agent_uuid = nil
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

        # Phase 4: Read agent UUID for sync
        agent_uuid = read_agent_uuid(ssh, via_ssh: true)
      end
      Result.new(success: true, agent_uuid: agent_uuid)
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
      agent_uuid = nil

      begin
        Rails.logger.debug "[RemoteInstallService] Connecting directly to target: #{user}@#{connect_host}"
        Net::SSH.start(connect_host, user, ssh_options) do |ssh|
          agent_uuid = perform_direct_install(ssh, connect_host)
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

      Result.new(success: true, agent_uuid: agent_uuid)
    rescue Net::SSH::AuthenticationFailed => e
      Rails.logger.error "Direct remote install failed: Authentication failed for #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise InstallError, "Installation failed: SSH authentication failed for #{connect_host}. Please check your credentials."
    rescue Errno::ECONNREFUSED => e
      Rails.logger.error "Direct remote install failed: Connection refused to #{connect_host}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise InstallError, "Installation failed: Connection refused to #{connect_host}. Is SSH running on the target?"
    rescue Errno::EHOSTUNREACH => e
      Rails.logger.error "Direct remote install failed: Host unreachable #{connect_host}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise InstallError, "Installation failed: Host unreachable (#{connect_host}). Check network connectivity."
    rescue Net::SSH::ConnectionTimeout, Errno::ETIMEDOUT => e
      Rails.logger.error "Direct remote install failed: Connection timed out to #{connect_host}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise InstallError, "Installation failed: Connection timed out to #{connect_host}. Check network or firewall settings."
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

      # Phase 3: Read agent UUID for sync
      read_agent_uuid(ssh, via_ssh: false)
    end

    # Local installation for localhost targets (no SSH required)
    def install_local
      agent_uuid = nil

      begin
        # Phase 1: Copy binary to temp location
        report_progress "Copying binary to /tmp/agent_bin_install"
        FileUtils.cp(@local_binary_path, "/tmp/agent_bin_install")

        # Phase 2: Move to final location using sudo
        report_progress "Moving binary to #{TARGET_BIN_PATH}"
        execute_local_command("mv /tmp/agent_bin_install #{TARGET_BIN_PATH}", use_sudo: true)

        # Phase 3: Configure agent service
        configure_target_local

        # Phase 4: Read agent UUID for sync
        agent_uuid = read_agent_uuid_local
      rescue => e
        Rails.logger.error "[RemoteInstallService] Local install failed: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        raise InstallError, "Installation failed: #{e.message}"
      end

      Result.new(success: true, agent_uuid: agent_uuid)
    end

    def configure_target_local
      report_progress "Configuring agent service locally"

      # chmod +x
      execute_local_command("chmod +x #{TARGET_BIN_PATH}", use_sudo: true)

      # Ensure node has a UUID for identity consistency
      node_uuid = ensure_node_uuid

      # Create systemd service file
      service_content = <<~SERVICE
        [Unit]
        Description=HPC Diagnostic Agent
        Documentation=https://github.com/yuka1981/diagnostic-tools
        Wants=network-online.target
        After=network-online.target

        [Service]
        Type=simple
        ExecStart=#{TARGET_BIN_PATH} start --server "#{@server_url}" --token "#{@agent_token}" --node-uuid "#{node_uuid}" --heartbeat-interval 60s --inventory-interval 60s
        Restart=always
        RestartSec=10
        User=root
        StandardOutput=journal
        StandardError=journal
        SyslogIdentifier=hpc-agent

        [Install]
        WantedBy=multi-user.target
      SERVICE

      service_file_path = "/etc/systemd/system/hpc-agent.service"
      tmp_service_path = "/tmp/hpc-agent.service"

      # Write to temp file first
      File.write(tmp_service_path, service_content)

      # Move to final location
      execute_local_command("mv #{tmp_service_path} #{service_file_path}", use_sudo: true)

      # Set ownership
      report_progress "Setting file ownership to root:root"
      execute_local_command("chown root:root #{TARGET_BIN_PATH} #{service_file_path}", use_sudo: true)

      # Set SELinux context if SELinux is available (for RHEL/CentOS/Fedora systems)
      # This is critical: both the binary AND the service file need correct contexts
      # - Binary needs bin_t to be executable
      # - Service file needs systemd_unit_file_t to be recognized by systemd
      report_progress "Setting SELinux context (if available)"
      selinux_cmd = <<~SELINUX
        if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
          restorecon -v #{TARGET_BIN_PATH} #{service_file_path} 2>/dev/null ||
          (chcon -t bin_t #{TARGET_BIN_PATH} 2>/dev/null || true;
           chcon -t systemd_unit_file_t #{service_file_path} 2>/dev/null || true);
        fi
      SELINUX
      execute_local_command(selinux_cmd, use_sudo: true)

      # Enable and start service
      report_progress "Starting agent service"
      execute_local_command("systemctl daemon-reload && systemctl enable --now hpc-agent", use_sudo: true)

      # Set dmidecode SUID
      report_progress "Ensuring dmidecode has SUID permission (4755)"
      execute_local_command("which dmidecode && chmod 4755 $(which dmidecode)", use_sudo: true)
    end

    def read_agent_uuid_local
      report_progress "Reading agent UUID for identity sync"

      uuid = File.read(AGENT_NODE_ID_PATH).strip
      if uuid.present?
        Rails.logger.info "[RemoteInstallService] Agent UUID: #{uuid}"
        uuid
      else
        Rails.logger.warn "[RemoteInstallService] Could not read agent UUID from #{AGENT_NODE_ID_PATH}"
        nil
      end
    rescue => e
      Rails.logger.warn "[RemoteInstallService] Failed to read agent UUID: #{e.message}"
      nil
    end

    def execute_local_command(cmd, use_sudo: false)
      full_cmd = build_local_command(cmd, use_sudo: use_sudo)

      # Mask password in logs
      log_cmd = @sudo_password.present? ? full_cmd.gsub(@sudo_password.to_s, "********") : full_cmd
      Rails.logger.debug "[RemoteInstallService] Executing locally: #{log_cmd}"

      stdout, stderr, status = Open3.capture3(full_cmd)

      report_log(stdout, "stdout") if stdout.present?
      # Filter out sudo password prompts from stderr
      filtered_stderr = stderr.lines.reject { |line| line.match?(/\[sudo\] password for/) }.join
      report_log(filtered_stderr, "stderr") if filtered_stderr.present?

      unless status.success?
        Rails.logger.error "[RemoteInstallService] Local command failed: #{log_cmd}"
        Rails.logger.error "[RemoteInstallService] Stderr: #{stderr}"
        # Use stdout if stderr is empty for better error messages
        error_output = filtered_stderr.strip.presence || stdout.strip
        raise InstallError, "Command failed (exit #{status.exitstatus}): #{error_output}"
      end

      stdout
    end

    def build_local_command(cmd, use_sudo:)
      return cmd unless use_sudo

      # Always use:
      # - timeout: prevents hanging if sudo blocks
      # - sudo -S: reads password from stdin (not TTY) to prevent TTY hang in background jobs
      escaped_cmd = Shellwords.escape(cmd)

      if @sudo_password.present?
        # Pipe password to sudo -S
        "echo #{Shellwords.escape(@sudo_password)} | timeout #{LOCAL_SUDO_TIMEOUT} sudo -S bash -c #{escaped_cmd}"
      else
        # No password - sudo -S will read empty stdin and fail quickly if password required
        # This is better than hanging forever waiting for TTY input
        "timeout #{LOCAL_SUDO_TIMEOUT} sudo -S bash -c #{escaped_cmd}"
      end
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
          # Ensure node has a UUID for identity consistency
          node_uuid = ensure_node_uuid

          service_content = <<~SERVICE
            [Unit]
            Description=HPC Diagnostic Agent
            Documentation=https://github.com/yuka1981/diagnostic-tools
            Wants=network-online.target
            After=network-online.target

            [Service]
            Type=simple
            ExecStart=#{TARGET_BIN_PATH} start --server "#{@server_url}" --token "#{@agent_token}" --node-uuid "#{node_uuid}" --heartbeat-interval 60s --inventory-interval 60s
            Restart=always
            RestartSec=10
            User=root
            StandardOutput=journal
            StandardError=journal
            SyslogIdentifier=hpc-agent

            [Install]
            WantedBy=multi-user.target
          SERVICE

          service_file_path = "/etc/systemd/system/hpc-agent.service"
          tmp_service_path = "/tmp/hpc-agent.service"

          # Write content to temp file using base64 encoding to avoid shell escaping issues
          encoded_content = Base64.strict_encode64(service_content)
          write_service_cmd = "echo '#{encoded_content}' | base64 -d > #{tmp_service_path}"
          execute_remote_command(ssh, write_service_cmd, password: nil)



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

      # 3.2.6 Set SELinux context if available (for RHEL/CentOS/Fedora systems)
      # This is critical: both the binary AND the service file need correct contexts
      # - Binary needs bin_t to be executable
      # - Service file needs systemd_unit_file_t to be recognized by systemd
      report_progress "Setting SELinux context (if available)"
      inner_selinux = <<~SELINUX.squish
        if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
          restorecon -v #{TARGET_BIN_PATH} #{service_file_path} 2>/dev/null ||
          (chcon -t bin_t #{TARGET_BIN_PATH} 2>/dev/null || true;
           chcon -t systemd_unit_file_t #{service_file_path} 2>/dev/null || true);
        fi
      SELINUX
      selinux_cmd = if via_ssh
                      remote_cmd = bash_c_command(inner_selinux)
                      "sudo -S ssh -o StrictHostKeyChecking=no #{target_user}@#{Shellwords.escape(@target_host)} #{Shellwords.escape(remote_cmd)}"
      else
                      "sudo -S #{bash_c_command(inner_selinux)}"
      end
      execute_remote_command(ssh, selinux_cmd, password: @sudo_password)

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

    # Read the agent's UUID from the remote node after installation
    # The agent generates and stores its UUID in /etc/hpc-agent/node_id
    # Note: The file is owned by root, so sudo is required to read it
    def read_agent_uuid(ssh, via_ssh: false)
      report_progress "Reading agent UUID for identity sync"

      inner_cmd = "cat #{AGENT_NODE_ID_PATH}"
      read_cmd = if via_ssh
                   "sudo -S ssh -o StrictHostKeyChecking=no #{target_user}@#{Shellwords.escape(@target_host)} #{Shellwords.escape("sudo #{inner_cmd}")}"
      else
                   "sudo -S #{inner_cmd}"
      end

      output = execute_remote_command(ssh, read_cmd, password: @sudo_password)
      uuid = output.strip

      if uuid.present?
        Rails.logger.info "[RemoteInstallService] Agent UUID: #{uuid}"
        uuid
      else
        Rails.logger.warn "[RemoteInstallService] Could not read agent UUID from #{AGENT_NODE_ID_PATH}"
        nil
      end
    rescue => e
      Rails.logger.warn "[RemoteInstallService] Failed to read agent UUID: #{e.message}"
      nil
    end

    # Ensure the node has a UUID - generate one if missing
    # This is used to inject the UUID into the service file for identity consistency
    def ensure_node_uuid
      return @node.uuid if @node&.uuid.present?

      # Generate a new UUID if node doesn't have one
      new_uuid = SecureRandom.uuid
      @node&.update_column(:uuid, new_uuid) if @node&.persisted?
      Rails.logger.info "[RemoteInstallService] Generated new node UUID: #{new_uuid}"
      new_uuid
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

    # Normalize server URL to base URL only (protocol + host + port)
    # Strips any path components to prevent routing errors
    # Example: "http://localhost:3000/nodes" -> "http://localhost:3000"
    def normalize_server_url(url)
      return url if url.blank?

      uri = URI.parse(url)

      # Check if URL has required components (scheme and host)
      if uri.scheme.blank? || uri.host.blank?
        Rails.logger.warn "[RemoteInstallService] Invalid server URL format (missing scheme or host): #{url}"
        return url
      end

      normalized = "#{uri.scheme}://#{uri.host}"
      normalized += ":#{uri.port}" if uri.port && !default_port?(uri)
      normalized
    rescue URI::InvalidURIError
      # If URL is malformed, return as-is and let it fail later with a clearer error
      Rails.logger.warn "[RemoteInstallService] Invalid server URL format: #{url}"
      url
    end

    def default_port?(uri)
      (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)
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
        # Use stdout if stderr is empty for better error messages
        error_output = clean_stderr.presence || stdout.strip
        # Log the full error context
        Rails.logger.error "[RemoteInstallService] Command failed: #{cmd}"
        Rails.logger.error "[RemoteInstallService] Error output: #{error_output}"

        raise InstallError, "Command failed with exit code #{exit_code}. Error: #{error_output}"
      end

      stdout
    end

    def report_log(data, stream)
      return unless @node

      ActionCable.server.broadcast("node_logs_#{@node.id}", { log: data, stream: stream })
    end
  end
end
