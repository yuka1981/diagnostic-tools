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

      unless result.success?
        ssh_target = "#{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}"
        error_detail = build_error_detail(result)
        return error_with_output("SSH command failed on #{ssh_target}: #{error_detail}", result, log_content)
      end

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
      ssh_target = "#{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}"
      error_with_output(
        "SSH authentication failed for #{ssh_target}: #{e.message}",
        nil,
        "SSH Authentication Error\nTarget: #{ssh_target}\n#{e.message}\n\nHint: Check SSH keys and user permissions"
      )
    rescue Net::SSH::ConnectionTimeout, Errno::ETIMEDOUT => e
      ssh_target = "#{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}"
      error_with_output(
        "SSH connection timeout to #{ssh_target}",
        nil,
        "SSH Connection Timeout\nTarget: #{ssh_target}\n#{e.message}\n\nHint: Check network connectivity and firewall rules"
      )
    rescue Errno::ECONNREFUSED => e
      ssh_target = "#{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}"
      error_with_output(
        "SSH connection refused by #{ssh_target}",
        nil,
        "SSH Connection Refused\nTarget: #{ssh_target}\n#{e.message}\n\nHint: Verify SSH service is running on the target node"
      )
    rescue Errno::EHOSTUNREACH, Errno::ENETUNREACH => e
      ssh_target = "#{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}"
      error_with_output(
        "SSH host unreachable: #{ssh_target}",
        nil,
        "Host Unreachable\nTarget: #{ssh_target}\n#{e.message}\n\nHint: Check network connectivity and routing"
      )
    rescue SocketError => e
      ssh_target = "#{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}"
      error_with_output(
        "SSH DNS/socket error for #{ssh_target}: #{e.message}",
        nil,
        "DNS/Socket Error\nTarget: #{ssh_target}\n#{e.message}\n\nHint: Check hostname resolution"
      )
    rescue Net::SSH::Exception => e
      ssh_target = "#{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}"
      error_with_output(
        "SSH error on #{ssh_target}: #{e.message}",
        nil,
        "SSH Error\nTarget: #{ssh_target}\n#{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}"
      )
    rescue StandardError => e
      ssh_target = "#{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}" rescue "unknown"
      error_with_output(
        "Unexpected error: #{e.class} - #{e.message}",
        nil,
        "Unexpected Error\nTarget: #{ssh_target}\n#{e.class}: #{e.message}\n\n#{e.backtrace&.first(10)&.join("\n")}"
      )
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
      builder = command_builder_for(agent_bin)
      builder.build
    end

    def command_builder_for(agent_bin)
      builder_class = command_builder_class
      builder_class.new(
        agent_bin: agent_bin,
        run_id: @run_id || generate_run_id,
        node_uuid: @target_node&.uuid,
        arguments: builder_arguments,
        server_url: @server_url,
        token: @agent_token
      )
    end

    def command_builder_class
      subcommand = @benchmark_recipe&.command || "hpcg"
      case subcommand
      when "hpcg"
        CommandBuilders::HpcgCommandBuilder
      when "mlc"
        CommandBuilders::MlcCommandBuilder
      else
        raise ArgumentError, "Unknown benchmark command: #{subcommand}"
      end
    end

    def builder_arguments
      # For HPCG, we need to pass: nx, ny, nz, rt (timeout), log_path
      # For MLC, we need to pass: profile, binary_path, modules, tests, log_dir
      args = argument_builder.merged_arguments.dup

      # Add timeout from recipe for HPCG
      if @benchmark_recipe&.timeout_seconds.present?
        args["rt"] = @benchmark_recipe.timeout_seconds
      end

      # Add log_path if provided
      args["log_path"] = @log_path if @log_path.present?

      args
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

    # Build a meaningful error message from SSH result
    # Prioritizes: stderr > stdout first line > exit code interpretation
    def build_error_detail(result)
      return "No result returned" if result.nil?

      parts = []

      # Add exit code with interpretation
      if result.exit_code
        parts << "exit_code=#{result.exit_code}"
        parts << exit_code_hint(result.exit_code)
      end

      # Add exit signal if present
      parts << "signal=#{result.exit_signal}" if result.exit_signal

      # Prefer stderr if available
      if result.error.present?
        parts << result.error.lines.first&.strip
      elsif result.output.present?
        # Fall back to first meaningful line from stdout
        first_line = result.output.lines.find { |l| l.strip.present? }&.strip
        parts << "stdout: #{first_line}" if first_line
      end

      detail = parts.compact.reject(&:blank?).join(" - ")
      detail.presence&.truncate(300) || "Command failed with no output"
    end

    # Provide hints for common exit codes
    def exit_code_hint(code)
      case code
      when 1 then "(general error)"
      when 2 then "(misuse of shell command)"
      when 126 then "(permission denied or not executable)"
      when 127 then "(command not found)"
      when 128 then "(invalid exit argument)"
      when 130 then "(terminated by Ctrl+C)"
      when 137 then "(killed by SIGKILL - out of memory?)"
      when 139 then "(segmentation fault)"
      when 143 then "(terminated by SIGTERM)"
      when 255 then "(SSH error or exit status out of range)"
      end
    end

    # Build comprehensive log content from SSH result
    def build_log_content(result)
      return "" if result.nil?

      parts = []

      # Add connection context for debugging
      parts << "=== SSH Connection Info ==="
      parts << "Target: #{target_user}@#{ssh_host}:#{@target_node.ssh_port || 22}"
      parts << "Working Dir: #{@work_dir}"
      parts << "Agent Path: #{@agent_path}"
      parts << ""

      # Add exit status info if available
      if result.exit_code || result.exit_signal
        parts << "=== Exit Status ==="
        parts << "Exit Code: #{result.exit_code}" if result.exit_code
        parts << "Exit Signal: #{result.exit_signal}" if result.exit_signal
        parts << ""
      end

      if result.output.present?
        parts << "=== SSH Stdout ==="
        parts << result.output
      end

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
