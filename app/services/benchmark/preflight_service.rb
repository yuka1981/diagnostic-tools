# frozen_string_literal: true

module Benchmark
  class PreflightService < ::SshExecutionService
    Result = Struct.new(:success, :checks, :config, :error, keyword_init: true) do
      def success?
        success
      end

      def failed_checks
        checks&.reject { |c| c[:passed] } || []
      end
    end

    Check = Struct.new(:name, :passed, :message, :details, keyword_init: true)

    HPCG_REPO_URL = "https://github.com/hpcg-benchmark/hpcg.git"

    def initialize(target_node, ssh_config: {}, server_url: nil, agent_token: nil)
      super(target_node, ssh_config: ssh_config)
      @work_dir = BenchmarkConfig.work_dir_for(@target_node)
      @agent_path = @target_node.try(:effective_agent_path) || "hpc-agent"
      @server_url = server_url
      @agent_token = agent_token
    end

    def call
      checks = []
      config = build_config_info

      # Check 1: SSH connectivity
      ssh_check = check_ssh_connectivity
      checks << ssh_check
      return Result.new(success: false, checks: checks, config: config, error: ssh_check.message) unless ssh_check.passed

      # Check 2: Working directory exists
      work_dir_check = check_working_directory
      checks << work_dir_check

      # Check 3: HPCG source setup (only if work_dir exists)
      if work_dir_check.passed
        hpcg_check = check_hpcg_source_setup
        checks << hpcg_check
      end

      # Check 4: Agent binary exists
      agent_check = check_agent_binary
      checks << agent_check

      # Check 5: API connectivity (only if server_url and token are provided)
      if @server_url.present? && @agent_token.present?
        api_check = check_api_connectivity
        checks << api_check
      end

      all_passed = checks.all?(&:passed)
      Result.new(success: all_passed, checks: checks, config: config)
    rescue Net::SSH::AuthenticationFailed => e
      checks << Check.new(name: "SSH Connectivity", passed: false, message: "Authentication failed: #{e.message}")
      Result.new(success: false, checks: checks, config: config, error: "SSH authentication failed")
    rescue Net::SSH::Exception => e
      checks << Check.new(name: "SSH Connectivity", passed: false, message: "SSH error: #{e.message}")
      Result.new(success: false, checks: checks, config: config, error: "SSH connection failed")
    rescue StandardError => e
      Result.new(success: false, checks: [], config: config, error: "Unexpected error: #{e.message}")
    end

    private

    def build_config_info
      {
        work_dir: @work_dir,
        work_dir_source: work_dir_source,
        agent_path: resolve_agent_path,
        node_hostname: @target_node.hostname,
        server_url: @server_url,
        api_configured: @server_url.present? && @agent_token.present?,
        token_source: token_source
      }
    end

    def token_source
      if @target_node&.api_token.present?
        :node
      elsif @agent_token.present?
        :global
      else
        :none
      end
    end

    def work_dir_source
      if @target_node&.benchmark_work_dir.present?
        :node
      elsif BenchmarkConfig.global_work_dir.present?
        :global
      else
        :default
      end
    end

    def check_ssh_connectivity
      result = execute_ssh_command("echo 'SSH_OK'")
      if result.success? && result.output&.include?("SSH_OK")
        Check.new(name: "SSH Connectivity", passed: true, message: "Connected successfully")
      else
        Check.new(name: "SSH Connectivity", passed: false, message: "Failed to connect: #{result.error}")
      end
    end

    def check_working_directory
      result = execute_ssh_command("test -d #{Shellwords.escape(@work_dir)} && echo 'DIR_EXISTS' || echo 'DIR_NOT_FOUND'")

      if result.success? && result.output&.include?("DIR_EXISTS")
        Check.new(
          name: "Working Directory",
          passed: true,
          message: "Directory exists",
          details: @work_dir
        )
      else
        Check.new(
          name: "Working Directory",
          passed: false,
          message: "Directory not found: #{@work_dir}",
          details: suggest_work_dir_fix
        )
      end
    end

    def check_hpcg_source_setup
      # Check for HPCG source structure:
      # 1. setup/ directory should exist (indicates HPCG source is cloned)
      # 2. setup/Make.Linux_Serial should exist (the build config we use)
      # Note: HPCG source is now auto-cloned by the agent if missing
      cmd = <<~BASH.squish
        cd #{Shellwords.escape(@work_dir)} &&
        if [ ! -d "setup" ]; then
          echo "NO_SOURCE";
        elif [ ! -f "setup/Make.Linux_Serial" ]; then
          echo "NO_MAKE_CONFIG";
        else
          echo "HPCG_READY";
        fi
      BASH

      result = execute_ssh_command(cmd)
      output = result.output&.strip

      case output
      when /HPCG_READY/
        Check.new(
          name: "HPCG Source",
          passed: true,
          message: "HPCG source is properly configured",
          details: "setup/Make.Linux_Serial found"
        )
      when /NO_SOURCE/
        # HPCG source will be auto-cloned by the agent - this is now informational
        Check.new(
          name: "HPCG Source",
          passed: true,
          message: "HPCG source will be cloned automatically",
          details: "The agent will clone from #{HPCG_REPO_URL} on first run"
        )
      when /NO_MAKE_CONFIG/
        Check.new(
          name: "HPCG Source",
          passed: false,
          message: "HPCG build configuration not found",
          details: "setup/Make.Linux_Serial is missing. The HPCG source may be incomplete or corrupted. Delete the directory and re-run."
        )
      else
        # If we can't verify, assume it will be auto-cloned
        Check.new(
          name: "HPCG Source",
          passed: true,
          message: "HPCG source status unknown (will be cloned if needed)",
          details: "Could not verify setup directory. The agent will clone automatically if needed."
        )
      end
    end

    def check_agent_binary
      agent_bin = resolve_agent_path
      # Check from work_dir context since that's where we'll run from
      cmd = "cd #{Shellwords.escape(@work_dir)} 2>/dev/null && test -x #{Shellwords.escape(agent_bin)} && echo 'AGENT_OK' || echo 'AGENT_NOT_FOUND'"
      result = execute_ssh_command(cmd)

      if result.success? && result.output&.include?("AGENT_OK")
        Check.new(
          name: "Agent Binary",
          passed: true,
          message: "Agent found and executable",
          details: agent_bin
        )
      else
        Check.new(
          name: "Agent Binary",
          passed: false,
          message: "Agent not found at: #{agent_bin}",
          details: "Ensure hpc-agent is installed and the path is correct"
        )
      end
    end

    def check_api_connectivity
      # Test API connectivity from the target node using curl
      # This verifies:
      # 1. The target node can reach the server URL
      # 2. The authentication token is valid
      health_url = "#{@server_url}/api/v1/health"
      cmd = <<~BASH.squish
        curl -s -o /dev/null -w '%{http_code}'
        -H 'Authorization: Bearer #{@agent_token}'
        -H 'Content-Type: application/json'
        --connect-timeout 10
        --max-time 15
        #{Shellwords.escape(health_url)}
      BASH

      result = execute_ssh_command(cmd)
      http_code = result.output&.strip

      case http_code
      when "200"
        Check.new(
          name: "API Connectivity",
          passed: true,
          message: "Server reachable, token valid",
          details: "Connected to #{@server_url}"
        )
      when "401"
        Check.new(
          name: "API Connectivity",
          passed: false,
          message: "Authentication failed - invalid token",
          details: "The server rejected the authentication token. Check API key configuration."
        )
      when "000", ""
        Check.new(
          name: "API Connectivity",
          passed: false,
          message: "Cannot reach server",
          details: "The target node cannot connect to #{@server_url}. Check network/firewall settings."
        )
      else
        Check.new(
          name: "API Connectivity",
          passed: false,
          message: "Server returned HTTP #{http_code}",
          details: "Unexpected response from #{health_url}. The server may be misconfigured."
        )
      end
    rescue StandardError => e
      Check.new(
        name: "API Connectivity",
        passed: false,
        message: "Connectivity check failed",
        details: "Error: #{e.message}"
      )
    end

    def resolve_agent_path
      if @agent_path == "hpc-agent"
        "../hpc-agent"
      elsif @agent_path.start_with?("/")
        @agent_path
      else
        "../#{@agent_path}"
      end
    end

    def suggest_work_dir_fix
      case work_dir_source
      when :node
        "This directory is configured in the node settings. Edit the node to change it."
      when :global
        "This directory is set in Settings > Agents. Change it there or override it in the node settings."
      else
        "Using default directory '#{BenchmarkConfig::DEFAULT_WORK_DIR}'. Configure it in Settings > Agents or in the node settings."
      end
    end
  end
end
