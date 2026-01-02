# frozen_string_literal: true

require "net/ssh"
require "net/ssh/gateway"
require "shellwords"

module Inventory
  class TriggerCollectService
    Result = Struct.new(:success, :output, :error, keyword_init: true) do
      def success?
        success
      end
    end

    DEFAULT_AGENT_PATH = "agent"
    DEFAULT_TIMEOUT = 30

    # Initialize the service
    # @param target_node [Node] The node to collect data from
    # @param gateway [Node, nil] Optional gateway/admin node to connect through (Legacy manual proxy)
    # @param ssh_config [Hash] SSH configuration (user, keys, timeout, verify_host_key)
    # @param agent_path [String] Path to the agent binary on remote host
    def initialize(target_node, gateway: nil, ssh_config: {}, agent_path: DEFAULT_AGENT_PATH)
      @target_node = target_node
      @gateway = gateway
      @ssh_config = build_ssh_config(ssh_config)
      @agent_path = agent_path
    end

    # Execute the SSH command to collect data from the target node
    # @return [Result] Success result with parsed JSON output, or error result
    # @raise [Net::SSH::ConnectionTimeout] When connection times out (retriable)
    # @raise [Net::SSH::AuthenticationFailed] When authentication fails (non-retriable)
    # @raise [Net::SSH::HostKeyMismatch] When host key verification fails (non-retriable)
    def call
      output = execute_ssh_command

      return error_result("Command returned empty output") if output.blank?

      parsed_output = parse_json(output)
      return parsed_output if parsed_output.is_a?(Result) # Error result

      @target_node.touch_last_seen

      Result.new(success: true, output: parsed_output)
    rescue JSON::ParserError => e
      error_result("JSON parse error: #{e.message}")
    end

    private

    def execute_ssh_command
      if SshConfig.use_jump_host?
        execute_via_gateway
      else
        execute_direct
      end
    end

    def execute_direct
      host = ssh_host
      user = target_user
      options = target_options

      Net::SSH.start(host, user, options) do |session|
        session.exec!(command)
      end
    end

    def execute_via_gateway
      gateway_host = SshConfig.jump_host
      gateway_user = SshConfig.jump_user || @ssh_config[:user]
      gateway_options = ssh_options.merge(port: SshConfig.jump_port)

      gateway = Net::SSH::Gateway.new(gateway_host, gateway_user, gateway_options)
      
      begin
        gateway.ssh(@target_node.ip || @target_node.hostname, target_user, target_options) do |session|
          session.exec!(command)
        end
      ensure
        gateway.shutdown!
      end
    end

    def target_user
      @target_node.ssh_user.presence || @ssh_config[:user]
    end

    def target_options
      ssh_options.merge(port: @target_node.ssh_port)
    end

    def ssh_host
      @gateway&.ip || @target_node.ip || @target_node.hostname
    end

    def ssh_options
      options = {
        keys: @ssh_config[:keys],
        timeout: @ssh_config[:timeout],
        non_interactive: true
      }

      # Only set verify_host_key if explicitly configured
      # Default behavior uses :secure (requires known_hosts)
      if @ssh_config[:verify_host_key]
        options[:verify_host_key] = @ssh_config[:verify_host_key]
      end

      options.compact
    end

    def command
      if @gateway
        # Connect through gateway, SSH to target node (Legacy manual proxy)
        # Use Shellwords.escape to prevent command injection
        "ssh #{Shellwords.escape(@target_node.hostname)} #{Shellwords.escape(@agent_path)} collect --json"
      else
        # Direct connection to target node
        "#{Shellwords.escape(@agent_path)} collect --json"
      end
    end

    def parse_json(output)
      JSON.parse(output, symbolize_names: true)
    rescue JSON::ParserError => e
      error_result("JSON parse error: #{e.message}")
    end

    def build_ssh_config(config)
      {
        user: config[:user] || default_ssh_user,
        keys: Array(config[:keys] || default_ssh_keys),
        timeout: config[:timeout] || default_ssh_timeout,
        verify_host_key: config[:verify_host_key] || default_verify_host_key
      }
    end

    def default_ssh_user
      Rails.application.credentials.dig(:ssh, :user) || ENV.fetch("SSH_USER", nil)
    end

    def default_ssh_keys
      key_path = Rails.application.credentials.dig(:ssh, :key_path) || ENV.fetch("SSH_KEY_PATH", nil)
      key_path ? [ key_path ] : []
    end

    def default_ssh_timeout
      Rails.application.credentials.dig(:ssh, :timeout) || ENV.fetch("SSH_TIMEOUT", DEFAULT_TIMEOUT).to_i
    end

    def default_verify_host_key
      # Default to nil (uses net-ssh default :secure behavior)
      # Can be overridden via credentials or env var for specific use cases
      config_value = Rails.application.credentials.dig(:ssh, :verify_host_key) || ENV.fetch("SSH_VERIFY_HOST_KEY", nil)
      config_value&.to_sym
    end

    def error_result(message)
      Result.new(success: false, output: nil, error: message)
    end
  end
end