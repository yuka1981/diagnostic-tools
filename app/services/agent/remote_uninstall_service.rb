# frozen_string_literal: true

require "net/ssh"

module Agent
  class RemoteUninstallService
    class UninstallError < StandardError; end

    TARGET_BIN_PATH = "/usr/local/bin/hpc-agent"
    SERVICE_FILE_PATH = "/etc/systemd/system/hpc-agent.service"

    STEPS = {
      connect: "Connecting to host",
      stop_service: "Stopping agent service",
      remove_files: "Removing files",
      reload_daemon: "Reloading systemd"
    }.freeze

    def initialize(target_host:, bastion_user: nil, bastion_host: nil, bastion_password: nil, sudo_password:, node: nil, on_progress: nil)
      @target_host = target_host
      validate_target_host!

      @node = node
      @bastion_host = bastion_host.presence
      @bastion_user = bastion_user.presence || "root"
      @bastion_password = bastion_password
      @sudo_password = sudo_password
      @on_progress = on_progress
    end

    def call
      if @node&.online?
        uninstall_via_websocket
      elsif use_bastion?
        uninstall_via_bastion
      else
        uninstall_direct
      end
    end

    private

    def target_user
      @node&.ssh_user.presence || "root"
    end

    def uninstall_via_websocket
      report_progress(:connect) # Reuse connect step to indicate contact

      # Broadcast command
      ActionCable.server.broadcast("agent_#{@node.uuid}", {
        type: "command",
        action: "uninstall",
        correlation_id: SecureRandom.uuid
      })

      report_progress(:stop_service)
      # We assume the agent handles the rest (files, stopping)

      true
    end

    def use_bastion?
      return false if localhost?
      @bastion_host.present?
    end

    def localhost?
      @target_host == "127.0.0.1" || @target_host == "localhost" || @target_host == "::1"
    end

    def uninstall_via_bastion
      # Fallback to sudo_password if bastion_password is blank
      effective_password = @bastion_password.presence || @sudo_password
      ssh_options = { password: effective_password, timeout: 10 }.compact

      report_progress(:connect)
      Net::SSH.start(@bastion_host, @bastion_user, ssh_options) do |ssh|
        # We run commands on the target via SSH from the bastion
        # sudo is executed on the bastion host
        target_spec = @target_host.include?(":") ? "[#{@target_host}]" : @target_host
        ssh_prefix = "sudo -S ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 #{target_user}@#{Shellwords.escape(target_spec)} "

        perform_cleanup(ssh, ssh_prefix)
      end
      true
    rescue => e
      Rails.logger.error "Remote uninstall via bastion failed: #{e.message}"
      raise UninstallError, "Uninstallation failed: #{e.message}"
    end

    def uninstall_direct
      # Fallback to sudo_password if bastion_password is blank
      effective_password = @bastion_password.presence || @sudo_password
      ssh_options = { password: effective_password, timeout: 10 }.compact
      user = target_user

      report_progress(:connect)
      Net::SSH.start(@target_host, user, ssh_options) do |ssh|
        perform_cleanup(ssh, "sudo -S ")
      end
      true
    rescue => e
      Rails.logger.error "Direct remote uninstall failed: #{e.message}"
      raise UninstallError, "Uninstallation failed: #{e.message}"
    end

    def perform_cleanup(ssh, prefix)
      report_progress(:stop_service)

      # Stop service (use timeout to prevent hanging)
      stop_cmd = "#{prefix}timeout 10s systemctl stop hpc-agent || true"
      execute_remote_command(ssh, stop_cmd, password: @sudo_password)

      # Disable service
      disable_cmd = "#{prefix}timeout 10s systemctl disable hpc-agent || true"
      execute_remote_command(ssh, disable_cmd, password: @sudo_password)

      report_progress(:remove_files)

      # Remove service file
      rm_service_cmd = "#{prefix}rm -f #{SERVICE_FILE_PATH}"
      execute_remote_command(ssh, rm_service_cmd, password: @sudo_password)

      # Remove binary
      rm_bin_cmd = "#{prefix}rm -f #{TARGET_BIN_PATH}"
      execute_remote_command(ssh, rm_bin_cmd, password: @sudo_password)

      report_progress(:reload_daemon)
      reload_cmd = "#{prefix}timeout 10s systemctl daemon-reload"
      execute_remote_command(ssh, reload_cmd, password: @sudo_password)
    end

    def report_progress(step)
      @on_progress&.call(step, STEPS[step])
    end

    def validate_target_host!
      unless @target_host =~ /\A[a-zA-Z0-9.-]+\z/
        raise UninstallError, "Invalid target host format: #{@target_host}"
      end
    end

    def execute_remote_command(ssh, cmd, password: nil)
      stdout = ""
      stderr = ""
      exit_code = nil

      Rails.logger.debug "[RemoteUninstallService] Executing: #{cmd.gsub(password.to_s, '********')}" if password.present?
      Rails.logger.debug "[RemoteUninstallService] Executing: #{cmd}" unless password.present?

      ssh.open_channel do |ch|
        ch.exec(cmd) do |channel, success|
          raise UninstallError, "Could not execute command: #{cmd}" unless success

          if password.present?
            channel.send_data("#{password}\n")
          end

          channel.on_data { |_c, data| stdout += data }
          channel.on_extended_data { |_c, _type, data| stderr += data }
          channel.on_request("exit-status") { |_c, data| exit_code = data.read_long }
        end
      end
      ssh.loop

      Rails.logger.debug "[RemoteUninstallService] Exit code: #{exit_code}"
      Rails.logger.debug "[RemoteUninstallService] Stdout: #{stdout}" if stdout.present?
      Rails.logger.debug "[RemoteUninstallService] Stderr: #{stderr}" if stderr.present?

      if exit_code != 0
        clean_stderr = stderr.gsub(/\[sudo\] password for .*: /, "").strip
        # Log the full error context
        Rails.logger.error "[RemoteUninstallService] Command failed: #{cmd}"
        Rails.logger.error "[RemoteUninstallService] Error output: #{clean_stderr}"
        
        raise UninstallError, "Command failed with exit code #{exit_code}. Error: #{clean_stderr}"
      end

      stdout
    end
  end
end
