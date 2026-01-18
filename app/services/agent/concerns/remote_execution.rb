# frozen_string_literal: true

require "net/ssh"
require "net/scp"
require "open3"

module Agent
  module Concerns
    # Shared SSH/local execution patterns for agent lifecycle operations
    module RemoteExecution
      extend ActiveSupport::Concern

      SERVICE_NAME = "hpc-agent"
      TARGET_BIN_PATH = "/usr/local/bin/hpc-agent"
      STAGING_DIR = "/tmp/hpc-agent-staging"

      def localhost?(host)
        return false if host.blank?

        host == "127.0.0.1" || host == "localhost" || host == "::1"
      end

      def localhost_target?
        localhost?(@node.ip) || localhost?(@node.hostname)
      end

      def use_bastion?
        return false if @node.direct?
        return false if localhost_target?
        return true if @node.custom_bastion? && @node.jump_host.present?
        return true if @node.global_bastion? && ::SshConfig.use_jump_host?

        false
      end

      def resolve_credentials(cache_key:)
        cached = Rails.cache.read(cache_key)

        @ssh_password = cached&.dig(:ssh_password) ||
                        @node.ssh_password

        @sudo_password = cached&.dig(:sudo_password) ||
                         @node.sudo_credential ||
                         @ssh_password
      end

      def ssh_user
        @node.ssh_user.presence || ::SshConfig.user || "root"
      end

      def ssh_keys
        key_path = ::SshConfig.key_path
        key_path.present? ? [ key_path ] : []
      end

      def ssh_options
        {
          timeout: 30,
          non_interactive: true,
          verify_host_key: :never,
          keys: ssh_keys,
          password: @ssh_password,
          append_all_supported_algorithms: true,
          auth_methods: [ "publickey", "password", "keyboard-interactive" ]
        }.compact
      end

      def report_progress(message)
        @on_progress&.call(message)
        Rails.logger.info "[#{self.class.name}] #{message}"

        return unless @node&.persisted?

        ActionCable.server.broadcast("node_logs_#{@node.id}", { log: "==> #{message}\n", stream: "meta" })
      end

      def broadcast_log(data, stream)
        return unless @node&.persisted?
        return if data.blank?
        return if data.match?(/\[sudo\] password for/)

        ActionCable.server.broadcast("node_logs_#{@node.id}", { log: data, stream: stream })
      end

      def execute_command(ssh, cmd, password: nil)
        stdout = ""
        stderr = ""
        exit_code = nil

        actual_cmd = if password.present? && cmd.include?("sudo")
                       if cmd.include?("sudo -S")
                         cmd.sub("sudo -S", "echo #{Shellwords.escape(password)} | sudo -S")
                       else
                         cmd.sub("sudo ", "echo #{Shellwords.escape(password)} | sudo -S ")
                       end
        else
                       cmd
        end

        log_cmd = password.present? ? actual_cmd.gsub(password.to_s, "********") : actual_cmd
        Rails.logger.debug "[#{self.class.name}] Executing: #{log_cmd}"

        ssh.open_channel do |ch|
          if password.present? && cmd.include?("sudo")
            ch.request_pty { |_, _| }
          end

          ch.exec(actual_cmd) do |channel, success|
            raise Agent::DeploymentError.new("Could not execute command", phase: :execute, details: { command: log_cmd }) unless success

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
          clean_stderr = stderr.gsub(/\[sudo\] password for .*:\s*|Sorry, try again\.\s*/i, "").strip
          clean_stdout = stdout.gsub(/\[sudo\] password for .*:\s*|Sorry, try again\.\s*/i, "").strip
          error_output = clean_stderr.presence || clean_stdout.presence || "Unknown error"
          raise Agent::DeploymentError.new(
            "Command failed (exit #{exit_code}): #{error_output}",
            phase: :execute,
            details: { command: log_cmd, exit_code: exit_code, stderr: clean_stderr, stdout: clean_stdout }
          )
        end

        stdout
      end

      def execute_local_command(cmd, use_sudo: false)
        full_cmd = build_local_command(cmd, use_sudo: use_sudo)

        log_cmd = @sudo_password.present? ? full_cmd.gsub(@sudo_password.to_s, "********") : full_cmd
        Rails.logger.debug "[#{self.class.name}] Executing locally: #{log_cmd}"

        stdout, stderr, status = Open3.capture3(full_cmd)

        broadcast_log(stdout, "stdout") if stdout.present?
        filtered_stderr = stderr.lines.reject { |line| line.match?(/\[sudo\] password for/) }.join
        broadcast_log(filtered_stderr, "stderr") if filtered_stderr.present?

        unless status.success?
          raise Agent::DeploymentError.new(
            "Command failed (exit #{status.exitstatus}): #{filtered_stderr.strip}",
            phase: :execute,
            details: { command: log_cmd, exit_code: status.exitstatus, stderr: filtered_stderr, stdout: stdout }
          )
        end

        stdout
      end

      def build_local_command(cmd, use_sudo:)
        if use_sudo && @sudo_password.present?
          "echo #{Shellwords.escape(@sudo_password)} | sudo -S bash -c #{Shellwords.escape(cmd)}"
        elsif use_sudo
          "sudo bash -c #{Shellwords.escape(cmd)}"
        else
          cmd
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

      def set_selinux_context(ssh, path, type:)
        selinux_cmd = <<~SELINUX.squish
          if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
            restorecon -v #{path} 2>/dev/null ||
            chcon -t #{type} #{path} 2>/dev/null || true;
          fi
        SELINUX

        if ssh.nil?
          execute_local_command(selinux_cmd, use_sudo: true)
        else
          cmd = build_remote_command(selinux_cmd, via_ssh: false, use_sudo: true)
          execute_command(ssh, cmd, password: @sudo_password)
        end
      end

      def capture_diagnostics(ssh, via_ssh: false)
        diagnostics = {}

        begin
          status_cmd = build_remote_command("systemctl status #{SERVICE_NAME} --no-pager -l 2>&1 | tail -20", via_ssh: via_ssh, use_sudo: true)
          diagnostics[:systemctl_status] = execute_command(ssh, status_cmd, password: @sudo_password)
        rescue Agent::DeploymentError => e
          diagnostics[:systemctl_status] = e.details[:stderr] || e.message
        end

        begin
          journal_cmd = build_remote_command("journalctl -u #{SERVICE_NAME} -n 20 --no-pager 2>&1", via_ssh: via_ssh, use_sudo: true)
          diagnostics[:journalctl_output] = execute_command(ssh, journal_cmd, password: @sudo_password)
        rescue Agent::DeploymentError => e
          diagnostics[:journalctl_output] = e.details[:stderr] || e.message
        end

        diagnostics
      end

      def generate_service_file(server_url:, api_token:, inventory_interval: 60, heartbeat_interval: 60)
        <<~SYSTEMD
          [Unit]
          Description=HPC Diagnostic Agent
          Documentation=https://github.com/yuka1981/diagnostic-tools
          Wants=network-online.target
          After=network-online.target

          [Service]
          Type=simple
          ExecStart=#{TARGET_BIN_PATH} start --server "#{server_url}" --token "#{api_token}" --heartbeat-interval #{heartbeat_interval}s --inventory-interval #{inventory_interval}s
          Restart=always
          RestartSec=10
          User=root
          StandardOutput=journal
          StandardError=journal
          SyslogIdentifier=hpc-agent

          [Install]
          WantedBy=multi-user.target
        SYSTEMD
      end
    end
  end
end
