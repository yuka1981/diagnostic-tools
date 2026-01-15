# frozen_string_literal: true

module Benchmark
  class TriggerRunService < ::SshExecutionService
    DEFAULT_AGENT_PATH = "hpc-agent"
    DEFAULT_TIMEOUT = 300 # Longer timeout for benchmarks

    # Initialize the service
    # @param target_node [Node] The node to run benchmark on
    # @param ssh_config [Hash] SSH configuration (user, keys, timeout, verify_host_key)
    # @param agent_path [String, nil] Optional override for path to the agent binary
    # @param work_dir [String, nil] Optional override for benchmark working directory
    # @param log_path [String, nil] Optional path for the benchmark log file
    # @param run_id [String, nil] Optional ID for the benchmark run
    # @param server_url [String, nil] Optional server URL for status updates
    # @param agent_token [String, nil] Optional agent token for status updates
    # @param benchmark_recipe [BenchmarkRecipe, nil] Optional recipe defining the benchmark
    # @param argument_overrides [Hash, nil] Optional user overrides for recipe defaults
    def initialize(target_node, ssh_config: {}, agent_path: nil, work_dir: nil, log_path: nil, run_id: nil, server_url: nil, agent_token: nil, benchmark_recipe: nil, argument_overrides: nil)
      super(target_node, ssh_config: ssh_config)
      @agent_path = agent_path || @target_node.try(:effective_agent_path) || DEFAULT_AGENT_PATH
      @work_dir = work_dir || BenchmarkConfig.work_dir_for(@target_node)
      @log_path = log_path
      @run_id = run_id
      @server_url = server_url
      @agent_token = agent_token
      @benchmark_recipe = benchmark_recipe
      @argument_overrides = argument_overrides || {}
    end

    # Get the merged arguments (recipe defaults + user overrides)
    # @return [Hash] Merged arguments for audit/snapshot purposes
    def merged_arguments
      return {} unless @benchmark_recipe

      argument_builder.merged_arguments
    end

    # Execute the SSH command to run benchmark
    # @return [Result] Success result or error result with full SSH output preserved
    def call
      result = execute_ssh_command(direct_command)

      # Build log content from SSH output (stdout + stderr)
      log_content = build_log_content(result)

      return error_with_output("SSH command failed", result, log_content) unless result.success?

      if result.output.blank?
        return error_with_output("Command returned empty output", result, log_content)
      end

      # Check for startup errors - the command now validates the process actually started
      if result.output.include?("STARTUP_ERROR:")
        error_msg = result.output.sub("STARTUP_ERROR:", "").strip
        return error_with_output("Benchmark failed to start: #{error_msg}", result, log_content)
      end

      # Expect "BENCHMARK_STARTED" prefix for successful startup
      unless result.output.include?("BENCHMARK_STARTED")
        return error_with_output("Unexpected output: #{result.output.truncate(200)}", result, log_content)
      end

      Result.new(success: true, output: log_content)
    rescue Net::SSH::AuthenticationFailed => e
      error_with_output("SSH authentication failed: #{e.message}", nil, "SSH Authentication Error\n#{e.message}")
    rescue Net::SSH::Exception => e
      error_with_output("SSH error: #{e.message}", nil, "SSH Error\n#{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}")
    rescue StandardError => e
      error_with_output("Unexpected error: #{e.message}", nil, "Unexpected Error\n#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}")
    end

    private

    def direct_command
      # Run in background with nohup to ensure it survives SSH disconnect
      # We validate that the process actually starts by:
      # 1. Capturing startup output to a log file
      # 2. Waiting briefly for the process to initialize
      # 3. Checking if the process is still running

      agent_bin = resolve_agent_path
      agent_cmd = build_agent_command(agent_bin)
      startup_log = "/tmp/hpcg_startup_#{@run_id || 'unknown'}.log"

      # Build a command that:
      # 1. Validates working directory exists
      # 2. Validates agent binary exists and is executable
      # 3. Starts the benchmark in background
      # 4. Waits 2 seconds and checks if process is still running
      # 5. Returns structured output for parsing
      work_dir_escaped = Shellwords.escape(@work_dir)
      <<~BASH.squish
        if [ ! -d #{work_dir_escaped} ]; then
          echo 'STARTUP_ERROR: Working directory #{@work_dir} not found';
          exit 1;
        fi &&
        cd #{work_dir_escaped} &&
        if [ ! -x #{Shellwords.escape(agent_bin)} ]; then
          echo 'STARTUP_ERROR: Agent binary not found or not executable at #{agent_bin}';
          exit 1;
        fi &&
        nohup #{agent_cmd} > #{Shellwords.escape(startup_log)} 2>&1 &
        HPCG_PID=$! &&
        sleep 2 &&
        if kill -0 $HPCG_PID 2>/dev/null; then
          echo "BENCHMARK_STARTED PID=$HPCG_PID";
        else
          echo "STARTUP_ERROR: Process exited immediately. Log: $(cat #{Shellwords.escape(startup_log)} | head -20)";
          exit 1;
        fi
      BASH
    end

    def resolve_agent_path
      # Heuristic: If agent_path is just "hpc-agent", it's likely in the parent dir of hpcg_source
      # If it is a relative path but not just "hpc-agent", we assume it is relative to the root.
      # If it is absolute, we use it as is.
      if @agent_path == "hpc-agent"
        "../hpc-agent"
      elsif @agent_path.start_with?("/")
        @agent_path
      else
        "../#{@agent_path}"
      end
    end

    def build_agent_command(agent_bin)
      # Set OMP_NUM_THREADS to use all physical cores for OpenMP parallelization
      # nproc returns the number of available processing units
      #
      # Command structure: hpc-agent [global-flags] <subcommand> [subcommand-flags]
      # The --node-uuid flag is a global persistent flag that must come before the subcommand
      cmd = "env OMP_NUM_THREADS=$(nproc) #{Shellwords.escape(agent_bin)}"

      # Inject node UUID to ensure identity consistency between Rails and Agent
      # This prevents the agent from generating a new UUID that doesn't match the node in Rails
      cmd += " --node-uuid #{Shellwords.escape(@target_node.uuid)}" if @target_node&.uuid.present?

      # Subcommand from recipe (defaults to hpcg for backwards compatibility)
      subcommand = @benchmark_recipe&.command || "hpcg"
      cmd += " #{Shellwords.escape(subcommand)}"
      cmd += " --id #{Shellwords.escape(@run_id || generate_run_id)}"
      cmd += " --build #{Shellwords.escape('make arch=Linux_OpenMP')}"
      cmd += " --run #{Shellwords.escape('./bin/xhpcg')}"

      # Add timeout from recipe (or default)
      timeout = @benchmark_recipe&.timeout_seconds || 60
      cmd += " --rt #{timeout}"

      # Add merged arguments from recipe defaults + overrides
      cmd += " #{argument_builder.call}" if @benchmark_recipe

      cmd += " --log-path #{Shellwords.escape(@log_path)}" if @log_path.present?
      cmd += " --server #{Shellwords.escape(@server_url)}" if @server_url.present?
      cmd += " --token #{Shellwords.escape(@agent_token)}" if @agent_token.present?
      cmd
    end

    def argument_builder
      @argument_builder ||= ArgumentBuilderService.new(
        defaults: @benchmark_recipe&.default_profile || {},
        overrides: @argument_overrides
      )
    end

    def generate_run_id
      @run_id || "hpcg-source-#{Time.current.strftime("%Y%m%d-%H%M")}"
    end

    # Build comprehensive log content from SSH result
    def build_log_content(result)
      return "" if result.nil?

      parts = []
      parts << "=== SSH Command Output ===" if result.output.present? || result.error.present?
      parts << result.output if result.output.present?

      if result.error.present?
        parts << ""
        parts << "=== SSH Stderr ==="
        parts << result.error
      end

      parts.join("\n")
    end

    # Create error result that preserves SSH output for debugging
    def error_with_output(message, _result, log_content)
      Result.new(success: false, output: log_content, error: message)
    end
  end
end
