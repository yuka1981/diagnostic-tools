# frozen_string_literal: true

require "net/ssh"

module Agent
  class RemoteUninstallService
    class UninstallError < StandardError; end

    TARGET_BIN_PATH = "/usr/local/bin/hpc-agent"
    SERVICE_FILE_PATH = "/etc/systemd/system/hpc-agent.service"

    def initialize(target_host:, bastion_user: nil, bastion_host: nil, bastion_password: nil, sudo_password:, on_progress: nil)
      @target_host = target_host
      validate_target_host!

      @bastion_host = bastion_host.presence
      @bastion_user = bastion_user.presence || "root"
      @bastion_password = bastion_password
      @sudo_password = sudo_password
      @on_progress = on_progress
    end

    def call
      if @bastion_host.present?
        uninstall_via_bastion
      else
        uninstall_direct
      end
    end

    private

    def uninstall_via_bastion
      ssh_options = { password: @bastion_password }.compact

      Net::SSH.start(@bastion_host, @bastion_user, ssh_options) do |ssh|
        report_progress "Connected to bastion host (#{@bastion_host})"

        # We run commands on the target via SSH from the bastion
        ssh_prefix = "sudo -S ssh -o StrictHostKeyChecking=no root@#{Shellwords.escape(@target_host)} "

        perform_cleanup(ssh, ssh_prefix)
      end
      true
    rescue => e
      Rails.logger.error "Remote uninstall via bastion failed: #{e.message}"
      raise UninstallError, "Uninstallation failed: #{e.message}"
    end

    def uninstall_direct
      ssh_options = { password: @bastion_password }.compact
      target_user = @bastion_user

      Net::SSH.start(@target_host, target_user, ssh_options) do |ssh|
        report_progress "Connected directly to target host (#{@target_host})"

        perform_cleanup(ssh, "sudo -S ")
      end
      true
    rescue => e
      Rails.logger.error "Direct remote uninstall failed: #{e.message}"
      raise UninstallError, "Uninstallation failed: #{e.message}"
    end

    def perform_cleanup(ssh, prefix)
      report_progress "Stopping and disabling agent service"

      # Stop service (ignore error if not exists)
      stop_cmd = "#{prefix}bash -c 'systemctl stop hpc-agent || true'"
      execute_remote_command(ssh, stop_cmd, password: @sudo_password)

      # Disable service
      disable_cmd = "#{prefix}bash -c 'systemctl disable hpc-agent || true'"
      execute_remote_command(ssh, disable_cmd, password: @sudo_password)

      report_progress "Removing service file and binary"

      # Remove service file
      rm_service_cmd = "#{prefix}rm -f #{SERVICE_FILE_PATH}"
      execute_remote_command(ssh, rm_service_cmd, password: @sudo_password)

      # Remove binary
      rm_bin_cmd = "#{prefix}rm -f #{TARGET_BIN_PATH}"
      execute_remote_command(ssh, rm_bin_cmd, password: @sudo_password)

      report_progress "Reloading systemd daemon"
      reload_cmd = "#{prefix}systemctl daemon-reload"
      execute_remote_command(ssh, reload_cmd, password: @sudo_password)
    end

    def report_progress(message)
      @on_progress&.call(message)
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
        clean_stderr = stderr.gsub(/\\[sudo\\] password for .*: /, "").strip
        # Some systemd commands might output to stderr even on success (warnings)
        # But if exit code is non-zero, it's an error.
        raise UninstallError, "Command failed with exit code #{exit_code}. Error: #{clean_stderr}"
      end

      stdout
    end
  end
end
