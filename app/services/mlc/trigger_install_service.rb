module Mlc
  class TriggerInstallService < ::SshExecutionService
    DEFAULT_TIMEOUT = 600 # 10 minutes for installation

    def initialize(installation:, installation_node:, server_url:, agent_token:, ssh_config: {})
      @installation = installation
      @installation_node = installation_node
      @server_url = server_url
      @agent_token = agent_token
      super(installation_node.node, ssh_config: ssh_config)
    end

    def call
      result = execute_ssh_command(build_ssh_command)

      unless result.success?
        return error_result("SSH command failed: #{result.error}")
      end

      if result.output.include?("INSTALL_STARTED")
        Result.new(success: true, output: result.output)
      elsif result.output.include?("STARTUP_ERROR:")
        error_msg = result.output.sub(/.*STARTUP_ERROR:\s*/, "").strip
        error_result("Installation failed to start: #{error_msg}")
      else
        error_result("Unexpected output: #{result.output.truncate(200)}")
      end
    rescue StandardError => e
      error_result("Unexpected error: #{e.message}")
    end

    private

    def build_ssh_command
      agent_bin = resolve_agent_path
      agent_cmd = build_agent_command

      <<~BASH.squish
        if [ ! -x #{Shellwords.escape(agent_bin)} ]; then
          echo 'STARTUP_ERROR: Agent binary not found at #{agent_bin}';
          exit 1;
        fi &&
        nohup #{agent_cmd} > /tmp/mlc_install_#{@installation.uuid}.log 2>&1 &
        INSTALL_PID=$! &&
        sleep 2 &&
        if kill -0 $INSTALL_PID 2>/dev/null; then
          echo "INSTALL_STARTED PID=$INSTALL_PID";
        else
          echo "STARTUP_ERROR: $(cat /tmp/mlc_install_#{@installation.uuid}.log | head -20)";
          exit 1;
        fi
      BASH
    end

    def build_agent_command
      parts = [
        resolve_agent_path,
        "mlc-install",
        "--tarball #{Shellwords.escape(@installation.source_path)}",
        "--binary-path #{Shellwords.escape(@installation.binary_path)}",
        "--install-dir #{Shellwords.escape(@installation.install_dir)}",
        "--module-dir #{Shellwords.escape(@installation.module_dir)}",
        "--id #{@installation.uuid}"
      ]

      if @server_url.present?
        parts << "--server #{Shellwords.escape(@server_url)}"
      end

      if @agent_token.present?
        parts << "--token #{Shellwords.escape(@agent_token)}"
      end

      parts.join(" ")
    end

    def resolve_agent_path
      @installation_node.node.agent_path.presence || SshSetting::DEFAULT_AGENT_PATH
    end
  end
end
