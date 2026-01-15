# frozen_string_literal: true

module Benchmark
  class CancelRunService < ::SshExecutionService
    DEFAULT_AGENT_PATH = "hpc-agent"

    # Initialize the service
    # @param benchmark_run [BenchmarkRun] The benchmark run to cancel
    # @param ssh_config [Hash] SSH configuration (user, keys, timeout, verify_host_key)
    # @param agent_path [String, nil] Optional override for path to the agent binary
    def initialize(benchmark_run, ssh_config: {}, agent_path: nil)
      @benchmark_run = benchmark_run
      @agent_path = agent_path || benchmark_run.node.try(:effective_agent_path) || DEFAULT_AGENT_PATH
      super(benchmark_run.node, ssh_config: ssh_config)
    end

    # Cancel the benchmark run
    # @return [Result] Success result or error result
    def call
      return error_result("Benchmark run not found") unless @benchmark_run
      return error_result("Cannot cancel completed run") if @benchmark_run.completed?

      if @benchmark_run.pending?
        cancel_pending_run
      elsif @benchmark_run.running?
        cancel_running_run
      else
        error_result("Run is in unexpected state: #{@benchmark_run.status}")
      end
    end

    private

    def cancel_pending_run
      # For pending runs, we simply update the status without SSH connection
      @benchmark_run.update!(
        status: :cancelled,
        finished_at: Time.current,
        error_message: "Cancelled from queue before execution"
      )

      Result.new(success: true, output: "Cancelled pending run")
    end

    def cancel_running_run
      result = execute_cancel_command

      # Update the run status regardless of SSH result
      # This ensures UI consistency even if the remote process already terminated
      update_run_as_cancelled(result)

      if result.success? || agent_reports_not_found?(result)
        Result.new(success: true, output: result.output)
      else
        Result.new(success: false, output: result.output, error: result.error)
      end
    rescue Net::SSH::AuthenticationFailed => e
      update_run_as_cancelled_with_error("SSH authentication failed")
      Result.new(success: false, error: "SSH authentication failed: #{e.message}")
    rescue Net::SSH::Exception => e
      update_run_as_cancelled_with_error("SSH error: #{e.message}")
      Result.new(success: false, error: "SSH error: #{e.message}")
    rescue StandardError => e
      update_run_as_cancelled_with_error("Cancel error: #{e.message}")
      Result.new(success: false, error: "Unexpected error: #{e.message}")
    end

    def execute_cancel_command
      cmd = build_cancel_command
      execute_ssh_command(cmd)
    end

    def build_cancel_command
      agent_bin = resolve_agent_path
      "#{agent_bin} cancel --uuid #{@benchmark_run.uuid}"
    end

    def resolve_agent_path
      if @agent_path == "hpc-agent"
        # When installed via agent installer, the binary is typically in /usr/local/bin
        "/usr/local/bin/hpc-agent"
      elsif @agent_path.start_with?("/")
        @agent_path
      else
        "/usr/local/bin/#{@agent_path}"
      end
    end

    def agent_reports_not_found?(result)
      # The agent returns status: "not_found" when there's no PID file
      # This is acceptable - it means the process already finished
      result.output&.include?('"status":"not_found"') ||
        result.output&.include?('"status": "not_found"')
    end

    def update_run_as_cancelled(result)
      message = if agent_reports_not_found?(result)
        "Process was not running (may have already completed)"
      else
        "Cancelled by user"
      end

      @benchmark_run.update!(
        status: :cancelled,
        finished_at: Time.current,
        error_message: message
      )
    end

    def update_run_as_cancelled_with_error(message)
      @benchmark_run.update!(
        status: :cancelled,
        finished_at: Time.current,
        error_message: "Cancelled (with error: #{message})"
      )
    end
  end
end
