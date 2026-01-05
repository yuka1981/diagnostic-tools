# frozen_string_literal: true

require "net/ssh"
require "net/ssh/gateway"
require "shellwords"

module Benchmark
  class TriggerRunService
    Result = Struct.new(:success, :output, :error, keyword_init: true) do
      def success?
        success
      end
    end

    DEFAULT_AGENT_PATH = "agent"
    DEFAULT_TIMEOUT = 300 # Longer timeout for benchmarks

    # Initialize the service
    # @param target_node [Node] The node to run benchmark on
    # @param ssh_config [Hash] SSH configuration (user, keys, timeout, verify_host_key)
    # @param agent_path [String, nil] Optional override for path to the agent binary
    def initialize(target_node, ssh_config: {}, agent_path: nil)
      @target_node = target_node
      @ssh_config = build_ssh_config(ssh_config)
      @agent_path = agent_path || @target_node.try(:effective_agent_path) || DEFAULT_AGENT_PATH
    end

    # Execute the SSH command to run benchmark
    # @return [Result] Success result or error result
    def call
      output = execute_ssh_command

      return error_result("Command returned empty output") if output.blank?

      # Parse output if needed, or just return success if the agent handles upload
      # For now, we assume the agent handles the upload logic internally if token is present
      Result.new(success: true, output: output)
    rescue Net::SSH::Exception => e
      error_result("SSH error: #{e.message}")
    rescue StandardError => e
      error_result("Unexpected error: #{e.message}")
    end

    private

    def execute_ssh_command
      if use_jump_host?
        execute_via_gateway
      else
        execute_direct
      end
    end

    def use_jump_host?
      @target_node.use_jump_host? || ::SshConfig.use_jump_host?
    end

    def execute_direct
      host = ssh_host
      user = target_user
      options = target_options

      Net::SSH.start(host, user, options) do |session|
        session.exec!(direct_command)
      end
    end

    def execute_via_gateway
      gateway_host = @target_node.jump_host.presence || ::SshConfig.jump_host
      gateway_user = @target_node.jump_user.presence || ::SshConfig.jump_user || @ssh_config[:user]
      gateway_port = @target_node.jump_port || ::SshConfig.jump_port
      gateway_options = ssh_options.merge(port: gateway_port)

      gateway = Net::SSH::Gateway.new(gateway_host, gateway_user, gateway_options)

      begin
        gateway.ssh(@target_node.ip || @target_node.hostname, target_user, target_options) do |session|
          session.exec!(direct_command)
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
      @target_node.ip || @target_node.hostname
    end

    def ssh_options
      options = {
        keys: @ssh_config[:keys],
        timeout: @ssh_config[:timeout],
        non_interactive: true
      }

      if @ssh_config[:verify_host_key]
        options[:verify_host_key] = @ssh_config[:verify_host_key]
      end

      options.compact
    end

    def direct_command
      # Construct the command with the correct flags
      # We rely on the agent having the server URL and token if configured via env vars on the host
      # Or we could pass them explicitly here if we had them available safely
      # For this iteration, we'll assume a basic run command
      "#{Shellwords.escape(@agent_path)} hpcg --id #{Shellwords.escape(generate_run_id)} 2>&1"
    end

    def generate_run_id
      "web-run-#{Time.now.to_i}"
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
      config_value = Rails.application.credentials.dig(:ssh, :verify_host_key) || ENV.fetch("SSH_VERIFY_HOST_KEY", nil)
      config_value&.to_sym
    end

    def error_result(message)
      Result.new(success: false, output: nil, error: message)
    end
  end
end
