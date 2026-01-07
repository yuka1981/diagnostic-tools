# frozen_string_literal: true

module Inventory
  class TriggerCollectService < ::SshExecutionService
    DEFAULT_AGENT_PATH = "hpc-agent"
    DEFAULT_TIMEOUT = 30

    # Initialize the service
    # @param target_node [Node] The node to collect data from
    # @param gateway [Node, nil] Optional gateway/admin node to connect through (Legacy manual proxy)
    # @param ssh_config [Hash] SSH configuration (user, keys, timeout, verify_host_key)
    # @param agent_path [String, nil] Optional override for path to the agent binary
    def initialize(target_node, gateway: nil, ssh_config: {}, agent_path: nil)
      super(target_node, ssh_config: ssh_config)
      @gateway = gateway
      @agent_path = agent_path || @target_node.try(:effective_agent_path) || DEFAULT_AGENT_PATH
    end

    # Execute the SSH command to collect data from the target node
    # @return [Result] Success result with parsed JSON output, or error result
    def call
      if @target_node.online?
        broadcast_command
        return Result.new(success: true, output: { async: true })
      end

      result = execute_ssh_command(command)

      return result unless result.success?
      return error_result("Command returned empty output") if result.output.blank?

      parsed_output = parse_json(result.output)
      return parsed_output if parsed_output.is_a?(Result) # Error result

      @target_node.touch_last_seen

      Result.new(success: true, output: parsed_output)
    end

    private

    def broadcast_command
      ActionCable.server.broadcast("agent_#{@target_node.uuid}", {
        type: "command",
        action: "collect_inventory",
        params: { force: true },
        correlation_id: SecureRandom.uuid
      })
    end

    # Override to support legacy manual gateway
    def execute_ssh_command(cmd)
      if @gateway
        # Connect through gateway, SSH to target node (Legacy manual proxy)
        # We manually construct the SSH command here because the base service handles
        # configured jump hosts, but this legacy gateway is passed explicitly.
        # Ideally, we should migrate legacy usage to the standard jump host config.
        # For now, we wrap it.

        # We need to construct the ssh command string to run on the gateway
        ssh_cmd = "ssh #{Shellwords.escape(@target_node.hostname)} #{cmd}"

        # We temporarily swap target_node to gateway to reuse base logic for connection
        original_node = @target_node
        @target_node = @gateway

        result = super(ssh_cmd)

        @target_node = original_node # Restore
        result
      else
        super(cmd)
      end
    end

    def command
      "#{Shellwords.escape(@agent_path)} collect --json 2>&1"
    end

    def parse_json(output)
      # Check for common shell errors first
      if output.include?("command not found")
        return error_result("Agent not found at '#{@agent_path}'. Please check if it's installed and in the PATH.")
      end

      if output.include?("Permission denied")
        return error_result("Permission denied when executing agent. Please check file permissions.")
      end

      # Check if output starts with "Error:" which is a common prefix for CLI errors
      if output.start_with?("Error:")
        return error_result("Agent error: #{output.sub("Error:", "").strip}")
      end

      JSON.parse(output, symbolize_names: true)
    rescue JSON::ParserError => e
      error_result("JSON parse error: #{e.message}. Raw output: #{output.truncate(200)}")
    end
  end
end
