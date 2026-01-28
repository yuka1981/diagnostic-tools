# frozen_string_literal: true

module Agent
  module Concerns
    # Shared service health check methods for agent lifecycle services
    # Handles systemd service status verification with sudo prompt filtering
    module ServiceHealthCheck
      SERVICE_NAME = "qis-agent"

      def verify_service_running(ssh)
        max_retries = 10
        retry_count = 0
        via_ssh = use_bastion?

        loop do
          status = get_service_status(ssh, via_ssh: via_ssh)

          if status == "active"
            report_progress "Service is running"
            return
          elsif status == "activating"
            retry_count += 1
            if retry_count >= max_retries
              raise Errors::ServiceError.new("Service stuck in activating state", phase: :verify)
            end
            report_progress "Service is starting... (#{retry_count}/#{max_retries})"
            sleep 1
          else
            diagnostics = ssh.nil? ? {} : capture_diagnostics(ssh, via_ssh: via_ssh)
            raise Errors::ServiceError.new(
              "Service failed to start. Status: #{status}",
              phase: :verify,
              details: diagnostics
            )
          end
        end
      end

      def get_service_status(ssh, via_ssh: false)
        if ssh.nil?
          output = execute_local_command("systemctl is-active #{SERVICE_NAME}", use_sudo: true)
          clean_sudo_output(output)
        else
          cmd = build_remote_command("systemctl is-active #{SERVICE_NAME}", via_ssh: via_ssh, use_sudo: true)
          output = execute_command(ssh, cmd, password: @sudo_password)
          clean_sudo_output(output)
        end
      rescue Errors::DeploymentError => e
        clean_sudo_output(e.details[:stdout]) || "unknown"
      end

      def clean_sudo_output(output)
        return nil if output.blank?

        output.gsub(/\[sudo\] password for \S+:\s*/, "").strip
      end
    end
  end
end
