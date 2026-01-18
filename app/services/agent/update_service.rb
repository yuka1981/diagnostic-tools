# frozen_string_literal: true

require_relative "lifecycle_service"

module Agent
  # Service to update the agent binary on a remote node
  # Includes auto-rollback on failure and service file regeneration
  class UpdateService < LifecycleService
    def initialize(node:, agent_release:, server_url: nil, api_token: nil, **options)
      super(node: node, agent_release: agent_release, **options)
      @server_url = server_url || default_server_url
      @api_token = api_token || @node.effective_api_token
      @local_checksum = nil
      @rollback_attempted = false
    end

    protected

    def operation_type
      :upgrade
    end

    def run_preflight_checks
      super

      check_node_busy!
      validate_release!
      find_agent_binary!
    end

    def execute_operation(ssh)
      binary_tempfile, @local_checksum = download_binary_to_temp
      report_progress "Starting agent update to #{@agent_release.version}"

      begin
        if ssh.nil?
          perform_local_update(binary_tempfile)
        else
          upload_and_update(ssh, binary_tempfile)
        end
      ensure
        binary_tempfile.close
        binary_tempfile.unlink
      end
    end

    def verify_health(ssh)
      report_progress "Verifying service health"
      verify_service_running(ssh)
    rescue ServiceError => e
      attempt_rollback(ssh)
      raise
    end

    def finalize
      @node.update_column(:agent_version, @agent_release.version)
      report_progress "Agent updated to #{@agent_release.version}"
    end

    def success_message
      "Agent updated to #{@agent_release.version}"
    end

    def should_regenerate_service_file?
      true # Always regenerate during update
    end

    private

    def check_node_busy!
      return if @force
      return unless @node.busy?

      raise NodeBusyError
    end

    def validate_release!
      raise ValidationError.new("Agent release must be persisted", phase: :preflight) unless @agent_release.persisted?
      raise ValidationError.new("Agent release is recalled and cannot be deployed", phase: :preflight) if @agent_release.recalled?
    end

    def find_agent_binary!
      @agent_binary = @agent_release.binary_for_arch(node_arch)
      @agent_binary ||= legacy_binary_wrapper

      raise ValidationError.new("No binary available for architecture: #{node_arch}", phase: :preflight) unless @agent_binary
    end

    def node_arch
      @node.arch.presence || "x86_64"
    end

    def legacy_binary_wrapper
      return nil unless @agent_release.binary.attached?

      LegacyBinaryWrapper.new(@agent_release)
    end

    def download_binary_to_temp
      report_progress "Downloading binary for #{node_arch} from storage"
      tempfile = Tempfile.new([ "agent-binary", "" ], binmode: true)
      binary_content = @agent_binary.binary.download
      tempfile.write(binary_content)
      tempfile.rewind

      local_checksum = Digest::SHA256.hexdigest(binary_content)
      report_progress "Local checksum: #{local_checksum[0..15]}..."

      [ tempfile, local_checksum ]
    end

    def perform_local_update(binary_tempfile)
      report_progress "Copying binary to staging"
      FileUtils.cp(binary_tempfile.path, "/tmp/agent_update")

      report_progress "Stopping agent service"
      execute_local_command("systemctl stop #{SERVICE_NAME}", use_sudo: true)

      report_progress "Verifying binary checksum"
      verify_local_checksum

      report_progress "Creating backup and installing new binary"
      swap_local_binary

      report_progress "Setting file permissions"
      execute_local_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", use_sudo: true)

      if should_regenerate_service_file?
        report_progress "Regenerating service file"
        deploy_local_service_file
      end

      report_progress "Setting SELinux context"
      set_selinux_context(nil, TARGET_BIN_PATH, type: "bin_t")

      report_progress "Starting agent service"
      execute_local_command("systemctl daemon-reload && systemctl start #{SERVICE_NAME}", use_sudo: true)
    end

    def upload_and_update(ssh, binary_tempfile)
      report_progress "Uploading binary to target"
      ssh.scp.upload!(binary_tempfile.path, "/tmp/agent_update")

      report_progress "Stopping agent service"
      systemctl_cmd("stop", ssh)

      report_progress "Verifying binary checksum"
      verify_remote_checksum(ssh)

      report_progress "Creating backup and installing new binary"
      swap_remote_binary(ssh)

      report_progress "Setting file permissions"
      set_remote_permissions(ssh)

      if should_regenerate_service_file?
        report_progress "Regenerating service file"
        deploy_remote_service_file(ssh)
      end

      report_progress "Setting SELinux context"
      set_selinux_context(ssh, TARGET_BIN_PATH, type: "bin_t")

      report_progress "Starting agent service"
      execute_command(ssh, build_remote_command("systemctl daemon-reload && systemctl start #{SERVICE_NAME}", via_ssh: false, use_sudo: true), password: @sudo_password)
    end

    def systemctl_cmd(action, ssh)
      cmd = build_remote_command("systemctl #{action} #{SERVICE_NAME}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end

    def verify_local_checksum
      output = execute_local_command("sha256sum /tmp/agent_update | awk '{print $1}'")
      actual = output.strip

      unless actual == @local_checksum
        raise ValidationError.new("Checksum mismatch! Expected: #{@local_checksum}, Got: #{actual}", phase: :verify)
      end
    end

    def verify_remote_checksum(ssh)
      cmd = build_remote_command("sha256sum /tmp/agent_update | awk '{print $1}'", via_ssh: false)
      output = execute_command(ssh, cmd)
      actual = output.strip

      unless actual == @local_checksum
        raise ValidationError.new("Checksum mismatch! Expected: #{@local_checksum}, Got: #{actual}", phase: :verify)
      end
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

    def swap_remote_binary(ssh)
      cmd = <<~CMD.squish
        if [ -f #{TARGET_BIN_PATH} ]; then
          mv #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak;
        fi &&
        mv /tmp/agent_update #{TARGET_BIN_PATH}
      CMD
      execute_command(ssh, build_remote_command(cmd, via_ssh: false, use_sudo: true), password: @sudo_password)
    end

    def set_remote_permissions(ssh)
      cmd = build_remote_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end

    def deploy_local_service_file
      service_content = generate_service_file(server_url: @server_url, api_token: @api_token)
      service_path = "/etc/systemd/system/#{SERVICE_NAME}.service"

      # Backup existing service file
      execute_local_command("cp #{service_path} #{service_path}.bak 2>/dev/null || true", use_sudo: true)

      # Write new service file via temp file
      tempfile = Tempfile.new("hpc-agent-service")
      tempfile.write(service_content)
      tempfile.close

      FileUtils.cp(tempfile.path, "/tmp/hpc-agent.service")
      execute_local_command("mv /tmp/hpc-agent.service #{service_path}", use_sudo: true)
      set_selinux_context(nil, service_path, type: "systemd_unit_file_t")

      tempfile.unlink
    end

    def deploy_remote_service_file(ssh)
      service_content = generate_service_file(server_url: @server_url, api_token: @api_token)
      service_path = "/etc/systemd/system/#{SERVICE_NAME}.service"

      # Backup existing service file
      backup_cmd = build_remote_command("cp #{service_path} #{service_path}.bak 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, backup_cmd, password: @sudo_password)

      # Write new service file via base64 encoding
      encoded_content = Base64.strict_encode64(service_content)
      write_cmd = build_remote_command("echo '#{encoded_content}' | base64 -d > /tmp/hpc-agent.service && mv /tmp/hpc-agent.service #{service_path}", via_ssh: false, use_sudo: true)
      execute_command(ssh, write_cmd, password: @sudo_password)

      set_selinux_context(ssh, service_path, type: "systemd_unit_file_t")
    end

    def verify_service_running(ssh)
      max_retries = 10
      retry_count = 0

      loop do
        status = get_service_status(ssh)

        if status == "active"
          report_progress "Service is running"
          return
        elsif status == "activating"
          retry_count += 1
          if retry_count >= max_retries
            raise ServiceError.new("Service stuck in activating state", phase: :verify)
          end
          report_progress "Service is starting... (#{retry_count}/#{max_retries})"
          sleep 1
        else
          diagnostics = ssh.nil? ? {} : capture_diagnostics(ssh)
          raise ServiceError.new(
            "Service failed to start. Status: #{status}",
            phase: :verify,
            details: diagnostics
          )
        end
      end
    end

    def get_service_status(ssh)
      if ssh.nil?
        output = execute_local_command("systemctl is-active #{SERVICE_NAME}", use_sudo: true)
        output.strip
      else
        cmd = build_remote_command("systemctl is-active #{SERVICE_NAME}", via_ssh: false, use_sudo: true)
        output = execute_command(ssh, cmd, password: @sudo_password)
        output.strip
      end
    rescue DeploymentError => e
      e.details[:stdout]&.strip || "unknown"
    end

    def attempt_rollback(ssh)
      return if @rollback_attempted

      @rollback_attempted = true
      report_progress "Service failed to start, attempting rollback..."

      begin
        if ssh.nil?
          perform_local_rollback
        else
          perform_remote_rollback(ssh)
        end

        sleep 3
        status = get_service_status(ssh)

        if status == "active"
          @agent_event.mark_rolled_back!(message: "Update failed, rolled back to previous version")
          report_progress "Rollback successful, restored previous version"
        else
          raise RollbackError.new("Rollback failed - service still not running", phase: :rollback)
        end
      rescue StandardError => e
        Rails.logger.error "[UpdateService] Rollback failed: #{e.message}"
        raise RollbackError.new("Rollback failed: #{e.message}", phase: :rollback, details: { original_error: e.class.name })
      end
    end

    def perform_local_rollback
      execute_local_command("pkill -9 hpc-agent || true", use_sudo: true)
      execute_local_command("mv #{TARGET_BIN_PATH}.bak #{TARGET_BIN_PATH}", use_sudo: true)
      execute_local_command("mv /etc/systemd/system/#{SERVICE_NAME}.service.bak /etc/systemd/system/#{SERVICE_NAME}.service 2>/dev/null || true", use_sudo: true)
      execute_local_command("systemctl daemon-reload && systemctl start #{SERVICE_NAME}", use_sudo: true)
    end

    def perform_remote_rollback(ssh)
      execute_command(ssh, build_remote_command("pkill -9 hpc-agent || true", via_ssh: false, use_sudo: true), password: @sudo_password)
      execute_command(ssh, build_remote_command("mv #{TARGET_BIN_PATH}.bak #{TARGET_BIN_PATH}", via_ssh: false, use_sudo: true), password: @sudo_password)
      execute_command(ssh, build_remote_command("mv /etc/systemd/system/#{SERVICE_NAME}.service.bak /etc/systemd/system/#{SERVICE_NAME}.service 2>/dev/null || true", via_ssh: false, use_sudo: true), password: @sudo_password)
      execute_command(ssh, build_remote_command("systemctl daemon-reload && systemctl start #{SERVICE_NAME}", via_ssh: false, use_sudo: true), password: @sudo_password)
    end

    def default_server_url
      Rails.application.routes.url_helpers.root_url(host: ENV.fetch("APP_HOST", "localhost:3000"))
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
  end
end
