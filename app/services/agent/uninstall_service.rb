# frozen_string_literal: true

require_relative "lifecycle_service"

module Agent
  # Service to uninstall the agent from a remote node
  class UninstallService < LifecycleService
    protected

    def operation_type
      :uninstall
    end

    def execute_operation(ssh)
      report_progress "Starting agent uninstallation"

      if ssh.nil?
        perform_local_uninstall
      else
        perform_remote_uninstall(ssh)
      end
    end

    def verify_health(_ssh)
      # No health verification for uninstall
    end

    def finalize
      @node.update_columns(agent_version: nil, source: :manual)
      report_progress "Agent uninstalled successfully"
    end

    def success_message
      "Agent uninstalled successfully"
    end

    def expected_version
      nil
    end

    private

    def perform_local_uninstall
      report_progress "Stopping agent service"
      execute_local_command("systemctl stop #{SERVICE_NAME} 2>/dev/null || true", use_sudo: true)

      report_progress "Disabling agent service"
      execute_local_command("systemctl disable #{SERVICE_NAME} 2>/dev/null || true", use_sudo: true)

      report_progress "Removing agent binary"
      execute_local_command("rm -f #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak", use_sudo: true)

      report_progress "Removing service file"
      execute_local_command("rm -f /etc/systemd/system/#{SERVICE_NAME}.service /etc/systemd/system/#{SERVICE_NAME}.service.bak", use_sudo: true)

      report_progress "Cleaning up staging files"
      execute_local_command("rm -rf #{STAGING_DIR} /tmp/agent_install /tmp/agent_update /tmp/hpc-agent.service", use_sudo: true)

      report_progress "Removing configuration directory"
      execute_local_command("rm -rf /etc/hpc-agent", use_sudo: true)

      report_progress "Reloading systemd"
      execute_local_command("systemctl daemon-reload", use_sudo: true)
    end

    def perform_remote_uninstall(ssh)
      report_progress "Stopping agent service"
      cmd = build_remote_command("systemctl stop #{SERVICE_NAME} 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Disabling agent service"
      cmd = build_remote_command("systemctl disable #{SERVICE_NAME} 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Removing agent binary"
      cmd = build_remote_command("rm -f #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Removing service file"
      cmd = build_remote_command("rm -f /etc/systemd/system/#{SERVICE_NAME}.service /etc/systemd/system/#{SERVICE_NAME}.service.bak", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Cleaning up staging files"
      cmd = build_remote_command("rm -rf #{STAGING_DIR} /tmp/agent_install /tmp/agent_update /tmp/hpc-agent.service", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Removing configuration directory"
      cmd = build_remote_command("rm -rf /etc/hpc-agent", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Reloading systemd"
      cmd = build_remote_command("systemctl daemon-reload", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end
  end
end
