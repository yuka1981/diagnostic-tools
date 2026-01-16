# frozen_string_literal: true

require "net/ssh"
require "net/scp"

module Agent
  # Custom error raised when attempting to update an agent on a busy node
  class NodeBusyError < StandardError
    def initialize(msg = "Update blocked: Node is currently busy (Pending/Running tasks).")
      super
    end
  end

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
      raise PatchError, "Agent release must have a binary attached" unless @agent_release.binary.attached?
      raise PatchError, "Agent release is recalled and cannot be deployed" if @agent_release.recalled?
    end

    def execute_update
      report_progress "Starting agent update to #{@agent_release.version} on #{@node.hostname}"

      # Download binary to temp file
      binary_tempfile = download_binary_to_temp

      begin
        if use_bastion?
          update_via_bastion(binary_tempfile)
        else
          update_direct(binary_tempfile)
        end
      ensure
        binary_tempfile.close
        binary_tempfile.unlink
      end

      Result.new(success: true, message: "Agent updated to #{@agent_release.version}")
    rescue => e
      Rails.logger.error "[PatchService] Update failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise PatchError, "Update failed: #{e.message}"
    end

    def download_binary_to_temp
      report_progress "Downloading binary from storage"
      tempfile = Tempfile.new([ "agent-binary", "" ], binmode: true)
      tempfile.write(@agent_release.binary.download)
      tempfile.rewind
      tempfile
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

      # Step 5: Start the service
      report_progress "Starting agent service"
      systemctl_cmd("start", ssh, via_ssh: via_ssh)

      # Step 6: Verify service is running
      report_progress "Verifying service status"
      verify_service_running(ssh, via_ssh: via_ssh)
    end

    def systemctl_cmd(action, ssh, via_ssh:)
      inner_cmd = "systemctl #{action} #{SERVICE_NAME}"
      cmd = build_remote_command(inner_cmd, via_ssh: via_ssh, use_sudo: true)
      execute_command(ssh, cmd, password: sudo_password)
    end

    def verify_checksum(ssh, via_ssh:)
      expected = @agent_release.checksum
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

    def verify_service_running(ssh, via_ssh:)
      inner_cmd = "systemctl is-active #{SERVICE_NAME}"
      cmd = build_remote_command(inner_cmd, via_ssh: via_ssh, use_sudo: true)

      output = execute_command(ssh, cmd, password: sudo_password)
      status = output.strip

      unless status == "active"
        raise PatchError, "Service failed to start. Status: #{status}"
      end

      report_progress "Service is running"
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
        ch.exec(cmd) do |channel, success|
          raise PatchError, "Could not execute command" unless success

          # Send password to sudo -S if provided
          if password.present?
            channel.send_data("#{password}\n")
          end

          channel.on_data do |_, data|
            stdout += data
            broadcast_log(data, "stdout")
          end
          channel.on_extended_data do |_, _, data|
            stderr += data
            broadcast_log(data, "stderr")
          end
          channel.on_request("exit-status") { |_, data| exit_code = data.read_long }
        end
      end
      ssh.loop

      if exit_code != 0
        Rails.logger.error "[PatchService] Command failed: #{log_cmd}"
        Rails.logger.error "[PatchService] Stderr: #{stderr}"
        raise PatchError, "Command failed (exit #{exit_code}): #{stderr.strip}"
      end

      stdout
    end

    def ssh_user
      @node.ssh_user.presence || ::SshConfig.user || "root"
    end

    def ssh_options
      {
        timeout: 30,
        non_interactive: true,
        verify_host_key: :never,
        keys: ssh_keys,
        password: @node.sudo_credential.presence
      }.compact
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
