# frozen_string_literal: true

require "net/ssh"
require "shellwords"

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
      ActiveSupport::Deprecation.new.warn(
        "Agent::RemoteUninstallService is deprecated. Use Agent::UninstallService instead. " \
        "Called from: #{caller_locations(1, 1)&.first}",
        caller_locations
      )

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
      "root"
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

        perform_cleanup(ssh, ssh_prefix, via_ssh: true)
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
      user = @bastion_user.presence || "root"

      connect_host = ssh_target_host

      begin
        report_progress(:connect)
        Net::SSH.start(connect_host, user, ssh_options) do |ssh|
          perform_cleanup(ssh, "sudo -S ", via_ssh: false)
        end
      rescue Net::SSH::ConnectionTimeout, Errno::ETIMEDOUT, Errno::EHOSTUNREACH => e
        # If we used IP and failed, try hostname if it's different
        if connect_host == @node&.ip && @target_host != @node&.ip
          Rails.logger.warn "[RemoteUninstallService] Connection to IP #{connect_host} failed: #{e.message}. Retrying with hostname: #{@target_host}"

          connect_host = @target_host
          retry
        end
        raise e
      end

      true
    rescue => e
      Rails.logger.error "Direct remote uninstall failed: #{e.message}"
      raise UninstallError, "Uninstallation failed: #{e.message}"
    end

    def ssh_target_host
      @node&.ip.present? ? @node.ip : @target_host
    end

    def perform_cleanup(ssh, prefix, via_ssh: false)
      report_progress(:stop_service)

      # Stop service (use timeout to prevent hanging)
      stop_cmd = "timeout 10s systemctl stop hpc-agent || true"
      execute_remote_command(ssh, build_command(prefix, stop_cmd, via_ssh: via_ssh), password: @sudo_password)

      # Disable service
      disable_cmd = "timeout 10s systemctl disable hpc-agent || true"
      execute_remote_command(ssh, build_command(prefix, disable_cmd, via_ssh: via_ssh), password: @sudo_password)

      report_progress(:remove_files)

      # Remove service file
      rm_service_cmd = "rm -f #{SERVICE_FILE_PATH}"
      execute_remote_command(ssh, build_command(prefix, rm_service_cmd, via_ssh: via_ssh), password: @sudo_password)

      # Remove binary
      rm_bin_cmd = "rm -f #{TARGET_BIN_PATH}"
      execute_remote_command(ssh, build_command(prefix, rm_bin_cmd, via_ssh: via_ssh), password: @sudo_password)

      # Remove temporary installation files
      rm_tmp_cmd = "rm -f /tmp/agent_bin_install /tmp/hpc-agent.service"
      execute_remote_command(ssh, build_command(prefix, rm_tmp_cmd, via_ssh: via_ssh), password: @sudo_password)

      report_progress(:reload_daemon)
      reload_cmd = "timeout 10s systemctl daemon-reload"
      execute_remote_command(ssh, build_command(prefix, reload_cmd, via_ssh: via_ssh), password: @sudo_password)
    end

    def build_command(prefix, cmd, via_ssh: false)
      # Wrap command for bash -c
      remote_cmd = bash_c_command(cmd)
      if via_ssh
        # When going through SSH, we need to escape the command so quotes are preserved
        "#{prefix}#{Shellwords.escape(remote_cmd)}"
      else
        # Direct connection, no additional escaping needed
        "#{prefix}#{remote_cmd}"
      end
    end

    def bash_c_command(cmd)
      # Wrap command in single quotes for bash -c, escaping existing single quotes
      quoted_cmd = "'" + cmd.gsub("'", "'\\\\''") + "'"
      "bash -c #{quoted_cmd}"
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
