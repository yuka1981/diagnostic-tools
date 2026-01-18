# frozen_string_literal: true

require "net/ssh"
require "net/scp"
require "open3"
require_relative "errors"

module Agent
  # Service to update the agent binary on a remote node
  # Includes safety checks to prevent updates while benchmarks are running
  class PatchService
    class PatchError < StandardError; end

    Result = Struct.new(:success, :message, keyword_init: true) do
      def success?
        success
      end
    end

    TARGET_BIN_PATH = "/usr/local/bin/hpc-agent"
    SERVICE_NAME = "hpc-agent"

    def initialize(node:, agent_release:, force: false, on_progress: nil)
      @node = node
      @agent_release = agent_release
      @force = force
      @on_progress = on_progress
    end

    def call
      # Step 0: Safety Check (Critical)
      check_node_busy!

      # Step 1: Validate prerequisites
      validate_prerequisites!

      # Step 2: Execute the update
      execute_update
    end

    private

    def check_node_busy!
      return if @force
      return unless @node.busy?

      raise NodeBusyError
    end

    def validate_prerequisites!
      raise PatchError, "Node must be persisted" unless @node.persisted?
      raise PatchError, "Agent release must be persisted" unless @agent_release.persisted?
      raise PatchError, "Agent release is recalled and cannot be deployed" if @agent_release.recalled?

      # Check for binary matching node's architecture
      @agent_binary = find_agent_binary
      raise PatchError, "No binary available for architecture: #{node_arch}" unless @agent_binary
    end

    # Find the AgentBinary matching the node's architecture
    # Falls back to legacy single-binary if no multi-arch binaries exist
    def find_agent_binary
      # First try the new multi-arch model
      agent_binary = @agent_release.binary_for_arch(node_arch)
      return agent_binary if agent_binary

      # Fall back to legacy single-binary attachment
      return nil unless @agent_release.binary.attached?

      # Create a compatibility wrapper for legacy binary
      LegacyBinaryWrapper.new(@agent_release)
    end

    def node_arch
      @node.arch.presence || "x86_64"
    end

    # Wrapper class for backward compatibility with legacy single-binary releases
    class LegacyBinaryWrapper
      attr_reader :checksum

      def initialize(agent_release)
        @agent_release = agent_release
        @checksum = agent_release.checksum
      end

      def binary
        @agent_release.binary
      end
    end

    def execute_update
      report_progress "Starting agent update to #{@agent_release.version} on #{@node.hostname}"

      # Download binary to temp file and calculate checksum
      binary_tempfile, @local_checksum = download_binary_to_temp

      begin
        if localhost_target?
          update_local(binary_tempfile)
        elsif use_bastion?
          update_via_bastion(binary_tempfile)
        else
          update_direct(binary_tempfile)
        end
      ensure
        binary_tempfile.close
        binary_tempfile.unlink
      end

      # Update node's agent_version to reflect the deployed release
      @node.update_column(:agent_version, @agent_release.version)

      Result.new(success: true, message: "Agent updated to #{@agent_release.version}")
    rescue => e
      Rails.logger.error "[PatchService] Update failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise PatchError, "Update failed: #{e.message}"
    end

    def download_binary_to_temp
      report_progress "Downloading binary for #{node_arch} from storage"
      tempfile = Tempfile.new([ "agent-binary", "" ], binmode: true)
      binary_content = @agent_binary.binary.download
      tempfile.write(binary_content)
      tempfile.rewind

      # Calculate SHA256 checksum locally for reliable verification
      local_checksum = Digest::SHA256.hexdigest(binary_content)
      report_progress "Local checksum: #{local_checksum[0..15]}..."

      [ tempfile, local_checksum ]
    end

    def use_bastion?
      return false if @node.direct?
      return false if localhost?(@node.ip) || localhost?(@node.hostname)
      return true if @node.custom_bastion? && @node.jump_host.present?
      return true if @node.global_bastion? && ::SshConfig.use_jump_host?

      false
    end

    def localhost?(host)
      return false if host.blank?

      host == "127.0.0.1" || host == "localhost" || host == "::1"
    end

    def localhost_target?
      localhost?(@node.ip) || localhost?(@node.hostname)
    end

    def update_local(binary_tempfile)
      report_progress "Executing local update (localhost detected)"

      # Copy binary to temp location
      report_progress "Copying binary to /tmp/agent_update"
      FileUtils.cp(binary_tempfile.path, "/tmp/agent_update")

      # Perform the update steps locally
      perform_local_update
    end

    def perform_local_update
      # Step 1: Stop the service
      report_progress "Stopping agent service"
      execute_local_command("systemctl stop #{SERVICE_NAME}", use_sudo: true)

      # Step 2: Verify checksum before swap
      report_progress "Verifying binary checksum"
      verify_local_checksum

      # Step 3: Swap binaries
      report_progress "Installing new binary"
      swap_local_binary

      # Step 4: Set permissions
      report_progress "Setting file permissions"
      execute_local_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", use_sudo: true)

      # Step 5: Set SELinux context (if SELinux is enabled)
      report_progress "Setting SELinux context"
      set_local_selinux_context

      # Step 6: Start the service
      report_progress "Starting agent service"
      execute_local_command("systemctl start #{SERVICE_NAME}", use_sudo: true)

      # Step 7: Verify service is running
      report_progress "Verifying service status"
      verify_local_service_running
    end

    def set_local_selinux_context
      selinux_cmd = <<~CMD.squish
        if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
          restorecon -v #{TARGET_BIN_PATH} 2>/dev/null ||
          chcon -t bin_t #{TARGET_BIN_PATH} 2>/dev/null || true;
        fi
      CMD
      execute_local_command(selinux_cmd, use_sudo: true)
    end

    def verify_local_checksum
      expected = @local_checksum
      output = execute_local_command("sha256sum /tmp/agent_update | awk '{print $1}'")
      actual = output.strip

      unless actual == expected
        raise PatchError, "Checksum mismatch! Expected: #{expected}, Got: #{actual}"
      end

      report_progress "Checksum verified: #{actual[0..15]}..."
    end

    def swap_local_binary
      cmd = <<~CMD.squish
        if [ -f #{TARGET_BIN_PATH} ]; then
          mv #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak;
        fi &&
        mv /tmp/agent_update #{TARGET_BIN_PATH}
      CMD
      execute_local_command(cmd, use_sudo: true)
    end

    def verify_local_service_running
      max_retries = 30
      retry_count = 0

      loop do
        # Use "|| true" to always return exit code 0, since systemctl is-active
        # returns exit code 3 for "activating" or "failed" status
        output = execute_local_command("systemctl is-active #{SERVICE_NAME} || true", use_sudo: true)
        status = output.strip

        if status == "active"
          report_progress "Service is running"
          return
        elsif status == "activating"
          retry_count += 1
          if retry_count >= max_retries
            diagnostics = capture_local_service_diagnostics
            raise PatchError, "Service stuck in activating state after #{max_retries}s. #{diagnostics}"
          end
          report_progress "Service is starting... (#{retry_count}/#{max_retries})"
          sleep 1
        else
          diagnostics = capture_local_service_diagnostics
          raise PatchError, "Service failed to start. Status: #{status}. #{diagnostics}"
        end
      end
    end

    def capture_local_service_diagnostics
      output = execute_local_command("journalctl -u #{SERVICE_NAME} -n 10 --no-pager 2>&1 || true", use_sudo: true)
      logs = output.lines.reject { |l| l.match?(/^\s*$/) }.last(5).join
      "Recent logs: #{logs.strip}"
    rescue StandardError => e
      "Could not capture logs: #{e.message}"
    end

    def execute_local_command(cmd, use_sudo: false)
      full_cmd = build_local_command(cmd, use_sudo: use_sudo)

      # Mask password in logs
      log_cmd = sudo_password.present? ? full_cmd.gsub(sudo_password.to_s, "********") : full_cmd
      Rails.logger.debug "[PatchService] Executing locally: #{log_cmd}"

      stdout, stderr, status = Open3.capture3(full_cmd)

      broadcast_log(stdout, "stdout") if stdout.present?
      # Filter out sudo password prompts from stderr
      filtered_stderr = stderr.lines.reject { |line| line.match?(/\[sudo\] password for/) }.join
      broadcast_log(filtered_stderr, "stderr") if filtered_stderr.present?

      unless status.success?
        Rails.logger.error "[PatchService] Local command failed: #{log_cmd}"
        Rails.logger.error "[PatchService] Stderr: #{stderr}"
        raise PatchError, "Command failed (exit #{status.exitstatus}): #{filtered_stderr.strip}"
      end

      stdout
    end

    def update_via_bastion(binary_tempfile)
      gateway_host = @node.jump_host.presence || ::SshConfig.jump_host
      gateway_user = @node.jump_user.presence || ::SshConfig.jump_user || ssh_user
      gateway_port = @node.jump_port || ::SshConfig.jump_port

      report_progress "Connecting via bastion #{gateway_host}"

      Net::SSH.start(gateway_host, gateway_user, ssh_options.merge(port: gateway_port)) do |bastion|
        # Upload to bastion temp location
        bastion_tmp = "/tmp/agent_update_#{SecureRandom.hex(8)}"
        report_progress "Uploading binary to bastion"
        bastion.scp.upload!(binary_tempfile.path, bastion_tmp)

        # Transfer from bastion to target
        report_progress "Transferring binary to target node"
        target_spec = @node.ip.presence || @node.hostname
        target_spec = "[#{target_spec}]" if target_spec.include?(":")

        scp_cmd = "scp -o StrictHostKeyChecking=no #{bastion_tmp} root@#{Shellwords.escape(target_spec)}:/tmp/agent_update"
        execute_command(bastion, scp_cmd)

        # Execute update on target
        perform_remote_update(bastion, via_ssh: true)

        # Cleanup bastion temp file
        bastion.exec!("rm -f #{bastion_tmp}")
      end
    end

    def update_direct(binary_tempfile)
      host = @node.ip.presence || @node.hostname
      report_progress "Connecting directly to #{host}"

      Net::SSH.start(host, ssh_user, ssh_options.merge(port: @node.ssh_port)) do |ssh|
        # Upload binary to temp location
        report_progress "Uploading binary to target"
        ssh.scp.upload!(binary_tempfile.path, "/tmp/agent_update")

        # Execute update
        perform_remote_update(ssh, via_ssh: false)
      end
    end

    def perform_remote_update(ssh, via_ssh:)
      # Step 1: Stop the service
      report_progress "Stopping agent service"
      systemctl_cmd("stop", ssh, via_ssh: via_ssh)

      # Step 2: Verify checksum before swap
      report_progress "Verifying binary checksum"
      verify_checksum(ssh, via_ssh: via_ssh)

      # Step 3: Swap binaries
      report_progress "Installing new binary"
      swap_binary(ssh, via_ssh: via_ssh)

      # Step 4: Set permissions
      report_progress "Setting file permissions"
      set_permissions(ssh, via_ssh: via_ssh)

      # Step 5: Set SELinux context (if SELinux is enabled)
      report_progress "Setting SELinux context"
      set_selinux_context(ssh, via_ssh: via_ssh)

      # Step 6: Start the service
      report_progress "Starting agent service"
      systemctl_cmd("start", ssh, via_ssh: via_ssh)

      # Step 7: Verify service is running
      report_progress "Verifying service status"
      verify_service_running(ssh, via_ssh: via_ssh)
    end

    def systemctl_cmd(action, ssh, via_ssh:)
      inner_cmd = "systemctl #{action} #{SERVICE_NAME}"
      cmd = build_remote_command(inner_cmd, via_ssh: via_ssh, use_sudo: true)
      execute_command(ssh, cmd, password: sudo_password)
    end

    def verify_checksum(ssh, via_ssh:)
      # Use locally calculated checksum for reliable verification
      # This ensures we compare SHA256 hex to SHA256 hex regardless of what's stored in DB
      expected = @local_checksum
      inner_cmd = "sha256sum /tmp/agent_update | awk '{print $1}'"
      cmd = build_remote_command(inner_cmd, via_ssh: via_ssh)

      output = execute_command(ssh, cmd)
      actual = output.strip

      unless actual == expected
        raise PatchError, "Checksum mismatch! Expected: #{expected}, Got: #{actual}"
      end

      report_progress "Checksum verified: #{actual[0..15]}..."
    end

    def swap_binary(ssh, via_ssh:)
      # Backup old binary (if exists) and move new one into place
      inner_cmd = <<~CMD.squish
        if [ -f #{TARGET_BIN_PATH} ]; then
          mv #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak;
        fi &&
        mv /tmp/agent_update #{TARGET_BIN_PATH}
      CMD
      cmd = build_remote_command(inner_cmd, via_ssh: via_ssh, use_sudo: true)
      execute_command(ssh, cmd, password: sudo_password)
    end

    def set_permissions(ssh, via_ssh:)
      inner_cmd = "chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}"
      cmd = build_remote_command(inner_cmd, via_ssh: via_ssh, use_sudo: true)
      execute_command(ssh, cmd, password: sudo_password)
    end

    def set_selinux_context(ssh, via_ssh:)
      # Set SELinux context for the binary (if SELinux is enabled)
      # This is required on RHEL/CentOS/Fedora systems for the binary to be executable
      selinux_cmd = <<~CMD.squish
        if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
          restorecon -v #{TARGET_BIN_PATH} 2>/dev/null ||
          chcon -t bin_t #{TARGET_BIN_PATH} 2>/dev/null || true;
        fi
      CMD
      cmd = build_remote_command(selinux_cmd, via_ssh: via_ssh, use_sudo: true)
      execute_command(ssh, cmd, password: sudo_password)
    end

    def verify_service_running(ssh, via_ssh:)
      max_retries = 30
      retry_count = 0

      loop do
        # Use "|| true" to always return exit code 0, since systemctl is-active
        # returns exit code 3 for "activating" or "failed" status
        inner_cmd = "systemctl is-active #{SERVICE_NAME} || true"
        cmd = build_remote_command(inner_cmd, via_ssh: via_ssh, use_sudo: true)

        output = execute_command(ssh, cmd, password: sudo_password)
        # Clean up output: remove password echo artifacts and PTY control chars
        status = output.gsub(/\r/, "").lines.last&.strip || "unknown"

        if status == "active"
          report_progress "Service is running"
          return
        elsif status == "activating"
          retry_count += 1
          if retry_count >= max_retries
            # Capture diagnostics before failing
            diagnostics = capture_service_diagnostics(ssh, via_ssh: via_ssh)
            raise PatchError, "Service stuck in activating state after #{max_retries}s. #{diagnostics}"
          end
          report_progress "Service is starting... (#{retry_count}/#{max_retries})"
          sleep 1
        else
          # Capture diagnostics for failed status
          diagnostics = capture_service_diagnostics(ssh, via_ssh: via_ssh)
          raise PatchError, "Service failed to start. Status: #{status}. #{diagnostics}"
        end
      end
    end

    def capture_service_diagnostics(ssh, via_ssh:)
      # Get recent journal logs for the service
      journal_cmd = "journalctl -u #{SERVICE_NAME} -n 10 --no-pager 2>&1 || true"
      cmd = build_remote_command(journal_cmd, via_ssh: via_ssh, use_sudo: true)

      begin
        output = execute_command(ssh, cmd, password: sudo_password)
        # Clean up output
        logs = output.gsub(/\r/, "").lines.reject { |l| l.match?(/^\s*$/) }.last(5).join
        "Recent logs: #{logs.strip}"
      rescue StandardError => e
        "Could not capture logs: #{e.message}"
      end
    end

    def build_remote_command(inner_cmd, via_ssh:, use_sudo: false)
      if via_ssh
        target_spec = @node.ip.presence || @node.hostname
        ssh_target = target_spec.include?(":") ? "[#{target_spec}]" : target_spec
        remote_cmd = use_sudo ? "sudo -S bash -c '#{inner_cmd.gsub("'", "'\\''")}'" : inner_cmd
        "ssh -o StrictHostKeyChecking=no root@#{Shellwords.escape(ssh_target)} #{Shellwords.escape(remote_cmd)}"
      else
        use_sudo ? "sudo -S bash -c '#{inner_cmd.gsub("'", "'\\''")}'" : inner_cmd
      end
    end

    def execute_command(ssh, cmd, password: nil)
      stdout = ""
      stderr = ""
      exit_code = nil

      # Mask password in logs
      log_cmd = password.present? ? cmd.gsub(password.to_s, "********") : cmd
      Rails.logger.debug "[PatchService] Executing: #{log_cmd}"

      ssh.open_channel do |ch|
        # Request PTY for sudo commands to ensure password can be sent
        if password.present? && cmd.include?("sudo")
          ch.request_pty { |_, _| }
        end

        ch.exec(cmd) do |channel, success|
          raise PatchError, "Could not execute command" unless success

          # Send password to sudo -S if provided
          if password.present?
            channel.send_data("#{password}\n")
          end

          channel.on_data do |_, data|
            stdout += data
            unless data.match?(/\[sudo\] password for |Password:|Sorry, try again/i)
              broadcast_log(data, "stdout")
            end
          end
          channel.on_extended_data do |_, _, data|
            stderr += data
            unless data.match?(/\[sudo\] password for |Password:|Sorry, try again/i)
              broadcast_log(data, "stderr")
            end
          end
          channel.on_request("exit-status") { |_, data| exit_code = data.read_long }
        end
      end
      ssh.loop

      if exit_code != 0
        clean_stderr = stderr.gsub(/\[sudo\] password for .*:\s*/i, "").strip
        Rails.logger.error "[PatchService] Command failed: #{log_cmd}"
        Rails.logger.error "[PatchService] Stderr: #{clean_stderr}"
        raise PatchError, "Command failed (exit #{exit_code}): #{clean_stderr}"
      end

      stdout
    end

    def ssh_user
      @node.ssh_user.presence || ::SshConfig.user || "root"
    end

    def build_local_command(cmd, use_sudo:)
      if use_sudo && sudo_password.present?
        "echo #{Shellwords.escape(sudo_password)} | sudo -S bash -c #{Shellwords.escape(cmd)}"
      elsif use_sudo
        "sudo bash -c #{Shellwords.escape(cmd)}"
      else
        cmd
      end
    end

    def ssh_options
      {
        timeout: 30,
        non_interactive: true,
        verify_host_key: :never,
        keys: ssh_keys,
        password: ssh_password
      }.compact
    end

    def ssh_password
      @node.ssh_password.presence
    end

    def ssh_keys
      key_path = ::SshConfig.key_path
      key_path.present? ? [ key_path ] : []
    end

    def report_progress(message)
      @on_progress&.call(message)
      Rails.logger.info "[PatchService] #{message}"

      # Broadcast to node logs channel if available
      return unless @node.persisted?

      ActionCable.server.broadcast("node_logs_#{@node.id}", { log: "==> #{message}\n", stream: "meta" })
    end

    def broadcast_log(data, stream)
      return unless @node.persisted?
      return if data.blank?

      # Don't broadcast sudo password prompts
      return if data.match?(/\[sudo\] password for/)

      ActionCable.server.broadcast("node_logs_#{@node.id}", { log: data, stream: stream })
    end

    def sudo_password
      @node.sudo_credential.presence
    end
  end
end
