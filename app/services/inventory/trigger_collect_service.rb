# frozen_string_literal: true

require "net/ssh"

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
    # @param gateway [Node, nil] Optional gateway/admin node to connect through
    # @param ssh_config [Hash] SSH configuration (user, keys, timeout)
    # @param agent_path [String] Path to the agent binary on remote host
    def initialize(target_node, gateway: nil, ssh_config: {}, agent_path: DEFAULT_AGENT_PATH)
      @target_node = target_node
      @gateway = gateway
      @ssh_config = build_ssh_config(ssh_config)
      @agent_path = agent_path
    end

    def call
      output = execute_ssh_command

      return error_result("Command returned empty output") if output.blank?

      parsed_output = parse_json(output)
      return parsed_output if parsed_output.is_a?(Result) # Error result

      @target_node.touch_last_seen

      Result.new(success: true, output: parsed_output)
    rescue Net::SSH::ConnectionTimeout => e
      error_result("Connection timeout: #{e.message}")
    rescue Net::SSH::AuthenticationFailed => e
      error_result("Authentication failed for user: #{e.message}")
    rescue Net::SSH::HostKeyMismatch => e
      error_result("Host key verification failed: #{e.message}")
    rescue Net::SSH::Exception => e
      error_result("SSH error: #{e.message}")
    rescue StandardError => e
      error_result("Unexpected error: #{e.message}")
    end

    private

    def execute_ssh_command
      host = ssh_host
      user = @ssh_config[:user]
      options = ssh_options

      Net::SSH.start(host, user, options) do |session|
        session.exec!(command)
      end
    end

    def ssh_host
      @gateway&.ip || @target_node.ip
    end

    def ssh_options
      {
        keys: @ssh_config[:keys],
        timeout: @ssh_config[:timeout],
        verify_host_key: :accept_new,
        non_interactive: true
      }.compact
    end

    def command
      if @gateway
        # Connect through gateway, SSH to target node
        "ssh #{@target_node.hostname} #{@agent_path} collect --json"
      else
        # Direct connection to target node
        "#{@agent_path} collect --json"
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
        timeout: config[:timeout] || default_ssh_timeout
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

    def error_result(message)
      Result.new(success: false, output: nil, error: message)
    end
  end
end
