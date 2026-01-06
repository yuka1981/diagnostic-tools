# frozen_string_literal: true

module Benchmark
  class TriggerRunService < ::SshExecutionService
    DEFAULT_AGENT_PATH = "agent"
    DEFAULT_TIMEOUT = 300 # Longer timeout for benchmarks

    # Initialize the service
    # @param target_node [Node] The node to run benchmark on
    # @param ssh_config [Hash] SSH configuration (user, keys, timeout, verify_host_key)
    # @param agent_path [String, nil] Optional override for path to the agent binary
    # @param log_path [String, nil] Optional path for the benchmark log file
    # @param run_id [String, nil] Optional ID for the benchmark run
    # @param server_url [String, nil] Optional server URL for status updates
    # @param agent_token [String, nil] Optional agent token for status updates
    def initialize(target_node, ssh_config: {}, agent_path: nil, log_path: nil, run_id: nil, server_url: nil, agent_token: nil)
      super(target_node, ssh_config: ssh_config)
      @agent_path = agent_path || @target_node.try(:effective_agent_path) || DEFAULT_AGENT_PATH
      @log_path = log_path
      @run_id = run_id
      @server_url = server_url
      @agent_token = agent_token
    end

    # Execute the SSH command to run benchmark
    # @return [Result] Success result or error result
    def call
      result = execute_ssh_command(direct_command)

      return result unless result.success?

      # Since we run in background, we might have empty output, but we expect "Benchmark started"
      if result.output.blank?
        return error_result("Command returned empty output")
      end

      # For now, we assume the agent handles the upload logic internally if token is present
      Result.new(success: true, output: result.output)
    rescue Net::SSH::Exception => e
      error_result("SSH error: #{e.message}")
    rescue StandardError => e
      error_result("Unexpected error: #{e.message}")
    end

    private

    def direct_command
      # Run in background with nohup to ensure it survives SSH disconnect
      # We use bash -c to handle complex command with redirects and backgrounding

      # Heuristic: If agent_path is just "agent", it's likely in the parent dir of hpcg_source
      # as seen in scripts/run_hpcg_from_source.sh.
      # If it is a relative path but not just "agent", we assume it is relative to the root.
      # If it is absolute, we use it as is.
      agent_bin = if @agent_path == "agent"
                    "../agent"
                  elsif @agent_path.start_with?("/")
                    @agent_path
                  else
                    "../#{@agent_path}"
                  end

      agent_cmd = "#{Shellwords.escape(agent_bin)} hpcg"
      agent_cmd += " --id #{Shellwords.escape(@run_id || generate_run_id)}"
      agent_cmd += " --build #{Shellwords.escape("make arch=Linux_Serial")}"
      agent_cmd += " --run #{Shellwords.escape("./bin/xhpcg")}"
      agent_cmd += " --nx 104 --ny 104 --nz 104 --rt 60"
      agent_cmd += " --log-path #{Shellwords.escape(@log_path)}" if @log_path.present?
      agent_cmd += " --server #{Shellwords.escape(@server_url)}" if @server_url.present?
      agent_cmd += " --token #{Shellwords.escape(@agent_token)}" if @agent_token.present?

      # Wrap in bash -c and ensure we CD into the correct directory first.
      # The echo is for the service to confirm the command was accepted.
      "bash -c 'cd hpcg_source && nohup #{agent_cmd} > /dev/null 2>&1 &' && echo 'Benchmark started'"
    end

    def generate_run_id
      @run_id || "hpcg-source-#{Time.current.strftime("%Y%m%d-%H%M")}"
    end
  end
end
