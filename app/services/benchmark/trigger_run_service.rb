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
    def initialize(target_node, ssh_config: {}, agent_path: nil, log_path: nil)
      super(target_node, ssh_config: ssh_config)
      @agent_path = agent_path || @target_node.try(:effective_agent_path) || DEFAULT_AGENT_PATH
      @log_path = log_path
    end

    # Execute the SSH command to run benchmark
    # @return [Result] Success result or error result
    def call
      result = execute_ssh_command(direct_command)

      return result unless result.success?
      return error_result("Command returned empty output") if result.output.blank?

      # Parse output if needed, or just return success if the agent handles upload
      # For now, we assume the agent handles the upload logic internally if token is present
      Result.new(success: true, output: result.output)
    rescue Net::SSH::Exception => e
      error_result("SSH error: #{e.message}")
    rescue StandardError => e
      error_result("Unexpected error: #{e.message}")
    end

    private

    def direct_command
      # We assume the environment has HPCG_DIR and other variables if needed,
      # but we'll use a more standard approach of cd into the source directory.
      # The requested command specifically mentions running in the source root.
      cmd = "cd hpcg_source && "
      cmd += "#{Shellwords.escape(@agent_path)} hpcg"
      cmd += " --id #{Shellwords.escape(generate_run_id)}"
      cmd += " --build #{Shellwords.escape("make arch=Linux_Serial")}"
      cmd += " --run #{Shellwords.escape("./bin/xhpcg")}"
      cmd += " --nx 104 --ny 104 --nz 104"
      cmd += " --rt 60"
      cmd += " --log-path #{Shellwords.escape(@log_path)}" if @log_path.present?
      cmd += " 2>&1"
      cmd
    end

    def generate_run_id
      "hpcg-source-#{Time.current.strftime("%Y%m%d-%H%M")}"
    end
  end
end
