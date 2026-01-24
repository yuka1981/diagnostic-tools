# frozen_string_literal: true

require_relative "lifecycle_service"
require_relative "concerns/service_health_check"

module Agent
  # Service to install the agent binary on a remote node
  class InstallService < LifecycleService
    include Concerns::ServiceHealthCheck

    def initialize(node:, server_url:, api_token:, agent_release: nil, binary_path: nil, **options)
      super(node: node, agent_release: agent_release, **options)
      @server_url = server_url
      @api_token = api_token
      @binary_path = binary_path
      @local_checksum = nil
    end

    protected

    def operation_type
      :install
    end

    def run_preflight_checks
      super
      validate_binary_source!
    end

    def execute_operation(ssh)
      prepare_binary
      report_progress "Starting agent installation"

      if ssh.nil?
        perform_local_install
      else
        upload_and_install(ssh)
      end
    end

    def verify_health(ssh)
      report_progress "Verifying service health"
      verify_service_running(ssh)
    end

    def finalize
      version = @agent_release&.version || extract_installed_version
      @node.update_columns(agent_version: version, source: :agent_push)
      report_progress "Agent installed successfully (version: #{version})"
    end

    def success_message
      "Agent installed (version: #{expected_version})"
    end

    def expected_version
      @agent_release&.version || "dev"
    end

    private

    def validate_binary_source!
      has_release = @agent_release&.persisted?
      has_binary_path = @binary_path.present? && File.exist?(@binary_path)

      unless has_release || has_binary_path
        raise Errors::ValidationError.new("Either agent_release or binary_path must be provided", phase: :preflight)
      end

      if has_release
        @agent_binary = @agent_release.binary_for_arch(node_arch) || legacy_binary_wrapper
        raise Errors::ValidationError.new("No binary available for architecture: #{node_arch}", phase: :preflight) unless @agent_binary
      end
    end

    def node_arch
      @node.arch.presence || "x86_64"
    end

    def legacy_binary_wrapper
      return nil unless @agent_release&.binary&.attached?

      UpdateService::LegacyBinaryWrapper.new(@agent_release)
    end

    def prepare_binary
      if @binary_path.present?
        @binary_tempfile = nil
        @local_checksum = Digest::SHA256.file(@binary_path).hexdigest
        report_progress "Using local binary: #{@binary_path}"
      else
        report_progress "Downloading binary for #{node_arch} from storage"
        @binary_tempfile = Tempfile.new([ "agent-binary", "" ], binmode: true)
        binary_content = @agent_binary.binary.download
        @binary_tempfile.write(binary_content)
        @binary_tempfile.rewind
        @local_checksum = Digest::SHA256.hexdigest(binary_content)
      end
      report_progress "Binary checksum: #{@local_checksum[0..15]}..."
    end

    def actual_binary_path
      @binary_path || @binary_tempfile.path
    end

    def perform_local_install
      report_progress "Copying binary to staging"
      FileUtils.cp(actual_binary_path, "/tmp/agent_install")

      stop_existing_service_if_running

      report_progress "Installing binary"
      execute_local_command("mv /tmp/agent_install #{TARGET_BIN_PATH}", use_sudo: true)

      report_progress "Setting file permissions"
      execute_local_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", use_sudo: true)

      write_agent_uuid(nil)

      report_progress "Deploying service file"
      deploy_local_service_file

      report_progress "Setting SELinux contexts"
      set_selinux_context(nil, TARGET_BIN_PATH, type: "bin_t")
      set_selinux_context(nil, "/etc/systemd/system/#{SERVICE_NAME}.service", type: "systemd_unit_file_t")

      report_progress "Enabling and starting service"
      execute_local_command("systemctl daemon-reload && systemctl enable #{SERVICE_NAME} && systemctl start #{SERVICE_NAME}", use_sudo: true)

      report_progress "Setting dmidecode SUID"
      execute_local_command("chmod 4755 $(which dmidecode) 2>/dev/null || true", use_sudo: true)
    ensure
      cleanup_binary_tempfile
    end

    def upload_and_install(ssh)
      if use_bastion?
        upload_and_install_via_bastion(ssh)
      else
        upload_and_install_direct(ssh)
      end
    ensure
      cleanup_binary_tempfile
    end

    # Direct connection: upload and execute directly on target
    def upload_and_install_direct(ssh)
      report_progress "Uploading binary to target"
      ssh.scp.upload!(actual_binary_path, "/tmp/agent_install")

      stop_existing_service_if_running_remote(ssh, via_ssh: false)

      report_progress "Installing binary"
      cmd = build_remote_command("mv /tmp/agent_install #{TARGET_BIN_PATH}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Setting file permissions"
      cmd = build_remote_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      write_agent_uuid(ssh, via_ssh: false)

      report_progress "Deploying service file"
      deploy_remote_service_file(ssh, via_ssh: false)

      report_progress "Setting SELinux contexts"
      set_selinux_context_remote(ssh, TARGET_BIN_PATH, type: "bin_t", via_ssh: false)
      set_selinux_context_remote(ssh, "/etc/systemd/system/#{SERVICE_NAME}.service", type: "systemd_unit_file_t", via_ssh: false)

      report_progress "Enabling and starting service"
      cmd = build_remote_command("systemctl daemon-reload && systemctl enable #{SERVICE_NAME} && systemctl start #{SERVICE_NAME}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Setting dmidecode SUID"
      cmd = build_remote_command("chmod 4755 $(which dmidecode) 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end

    # Bastion connection: upload to bastion, then SCP and execute on target via SSH
    def upload_and_install_via_bastion(ssh)
      report_progress "Uploading binary to bastion"
      ssh.scp.upload!(actual_binary_path, "/tmp/agent_install")

      report_progress "Transferring binary from bastion to target"
      scp_to_target(ssh, "/tmp/agent_install", "/tmp/agent_install")

      stop_existing_service_if_running_remote(ssh, via_ssh: true)

      report_progress "Installing binary on target"
      cmd = build_remote_command("mv /tmp/agent_install #{TARGET_BIN_PATH}", via_ssh: true, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Setting file permissions on target"
      cmd = build_remote_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", via_ssh: true, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      write_agent_uuid(ssh, via_ssh: true)

      report_progress "Deploying service file to target"
      deploy_remote_service_file(ssh, via_ssh: true)

      report_progress "Setting SELinux contexts on target"
      set_selinux_context_remote(ssh, TARGET_BIN_PATH, type: "bin_t", via_ssh: true)
      set_selinux_context_remote(ssh, "/etc/systemd/system/#{SERVICE_NAME}.service", type: "systemd_unit_file_t", via_ssh: true)

      report_progress "Enabling and starting service on target"
      cmd = build_remote_command("systemctl daemon-reload && systemctl enable #{SERVICE_NAME} && systemctl start #{SERVICE_NAME}", via_ssh: true, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Setting dmidecode SUID on target"
      cmd = build_remote_command("chmod 4755 $(which dmidecode) 2>/dev/null || true", via_ssh: true, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      # Cleanup temp file on bastion
      execute_command(ssh, "rm -f /tmp/agent_install", password: @sudo_password)
    end

    def stop_existing_service_if_running
      execute_local_command("systemctl stop #{SERVICE_NAME} 2>/dev/null || true", use_sudo: true)
    end

    def stop_existing_service_if_running_remote(ssh, via_ssh:)
      cmd = build_remote_command("systemctl stop #{SERVICE_NAME} 2>/dev/null || true", via_ssh: via_ssh, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end

    def deploy_local_service_file
      service_content = generate_service_file(server_url: @server_url, api_token: @api_token, node_uuid: @node.uuid)
      service_path = "/etc/systemd/system/#{SERVICE_NAME}.service"

      tempfile = Tempfile.new("hpc-agent-service")
      tempfile.write(service_content)
      tempfile.close

      FileUtils.cp(tempfile.path, "/tmp/hpc-agent.service")
      execute_local_command("mv /tmp/hpc-agent.service #{service_path}", use_sudo: true)

      tempfile.unlink
    end

    def deploy_remote_service_file(ssh, via_ssh:)
      service_content = generate_service_file(server_url: @server_url, api_token: @api_token, node_uuid: @node.uuid)
      service_path = "/etc/systemd/system/#{SERVICE_NAME}.service"

      encoded_content = Base64.strict_encode64(service_content)
      write_cmd = build_remote_command("echo #{encoded_content} | base64 -d > /tmp/hpc-agent.service && mv /tmp/hpc-agent.service #{service_path}", via_ssh: via_ssh, use_sudo: true)
      execute_command(ssh, write_cmd, password: @sudo_password)
    end

    def write_agent_uuid(ssh, via_ssh: false)
      report_progress "Writing node UUID"
      uuid_path = "/etc/hpc-agent/node_id"

      if ssh.nil?
        execute_local_command("mkdir -p /etc/hpc-agent", use_sudo: true)
        execute_local_command("echo #{@node.uuid} > #{uuid_path}", use_sudo: true)
      else
        cmd = build_remote_command(
          "mkdir -p /etc/hpc-agent && echo #{@node.uuid} > #{uuid_path}",
          via_ssh: via_ssh, use_sudo: true
        )
        execute_command(ssh, cmd, password: @sudo_password)
      end
    end

    def set_selinux_context_remote(ssh, path, type:, via_ssh:)
      selinux_cmd = <<~SELINUX.squish
        if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
          restorecon -v #{path} 2>/dev/null ||
          chcon -t #{type} #{path} 2>/dev/null || true;
        fi
      SELINUX

      cmd = build_remote_command(selinux_cmd, via_ssh: via_ssh, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end

    def extract_installed_version
      # Try to get version from installed binary
      if localhost_target?
        output = execute_local_command("#{TARGET_BIN_PATH} version 2>/dev/null || echo 'dev'")
        output.strip.presence || "dev"
      else
        "dev"
      end
    rescue StandardError
      "dev"
    end

    def cleanup_binary_tempfile
      return unless @binary_tempfile

      @binary_tempfile.close
      @binary_tempfile.unlink
    rescue StandardError
      # Ignore cleanup errors
    end
  end
end
