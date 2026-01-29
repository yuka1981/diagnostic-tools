# frozen_string_literal: true

require "net/ssh"
require "net/ssh/gateway"
require "shellwords"
require "open3"

class SshExecutionService
  Result = Struct.new(:success, :output, :error, :exit_code, :exit_signal, keyword_init: true) do
    def success?
      success
    end

    # Human-readable error summary for debugging
    def error_summary
      parts = []
      parts << "exit_code=#{exit_code}" if exit_code && exit_code != 0
      parts << "exit_signal=#{exit_signal}" if exit_signal
      parts << error.to_s.lines.first&.strip if error.present?
      parts.join(", ")
    end
  end

  DEFAULT_TIMEOUT = 30

  # Initialize the service
  # @param target_node [Node] The node to connect to
  # @param ssh_config [Hash] SSH configuration (user, keys, timeout, verify_host_key)
  def initialize(target_node, ssh_config: {})
    @target_node = target_node
    @ssh_config = build_ssh_config(ssh_config)
  end

  private

  def execute_ssh_command(cmd, &block)
    if localhost_target?
      execute_local(cmd, &block)
    elsif direct_connection_required?
      execute_direct(cmd, &block)
    elsif use_jump_host?
      execute_via_gateway(cmd, &block)
    else
      execute_direct(cmd, &block)
    end
  end

  def localhost_target?
    localhost?(@target_node.ip) || localhost?(@target_node.hostname)
  end

  def direct_connection_required?
    @target_node.effective_ssh_connect_method == "direct"
  end

  def localhost?(host)
    return false if host.blank?

    host == "127.0.0.1" || host == "localhost" || host == "::1"
  end

  def execute_local(cmd, &block)
    stdout_data = ""
    stderr_data = ""

    Rails.logger.debug "[SshExecutionService] Executing locally: #{cmd}"

    stdout, stderr, status = Open3.capture3(cmd)

    stdout_data = stdout
    stderr_data = stderr

    yield(stdout, :stdout) if block_given? && stdout.present?
    yield(stderr, :stderr) if block_given? && stderr.present?

    Result.new(
      success: status.success?,
      output: stdout_data,
      error: stderr_data,
      exit_code: status.exitstatus,
      exit_signal: nil
    )
  rescue StandardError => e
    Result.new(success: false, output: "", error: e.message, exit_code: nil, exit_signal: nil)
  end

  def use_jump_host?
    # Only global_bastion connection method uses the jump host
    # direct connection method bypasses the bastion
    effective_method = @target_node.effective_ssh_connect_method
    return true if effective_method == "global_bastion" && ::SshConfig.use_jump_host?

    false
  end

  def execute_direct(cmd, &block)
    host = ssh_host
    user = target_user
    options = target_options

    Net::SSH.start(host, user, options) do |session|
      execute_on_session(session, cmd, &block)
    end
  end

  def execute_via_gateway(cmd, &block)
    # Bastion settings are now only in global SshConfig
    gateway_host = ::SshConfig.jump_host
    gateway_user = ::SshConfig.jump_user || @ssh_config[:user]
    gateway_port = ::SshConfig.jump_port
    gateway_options = ssh_options.merge(port: gateway_port)

    gateway = Net::SSH::Gateway.new(gateway_host, gateway_user, gateway_options)

    begin
      output = gateway.ssh(@target_node.ip || @target_node.hostname, target_user, target_options) do |session|
        execute_on_session(session, cmd, &block)
      end
      # When using gateway.ssh block return value is returned.
      output
    ensure
      gateway.shutdown!
    end
  end

  def execute_on_session(session, cmd)
    stdout_data = ""
    stderr_data = ""
    exit_code = nil
    exit_signal = nil

    channel = session.open_channel do |ch|
      ch.exec(cmd) do |c, success|
        raise "Could not execute command" unless success

        ch.on_data do |_, data|
          stdout_data += data.to_s
          yield(data, :stdout) if block_given?
        end

        ch.on_extended_data do |_, _type, data|
          stderr_data += data.to_s
          yield(data, :stderr) if block_given?
        end


        c.on_request("exit-status") do |_, data|
          exit_code = data.read_long
        end

        c.on_request("exit-signal") do |_, data|
          exit_signal = data.read_long
        end
      end
    end
    session.loop

    success = exit_code == 0 && exit_signal.nil?
    Result.new(success: success, output: stdout_data, error: stderr_data, exit_code: exit_code, exit_signal: exit_signal)
  rescue StandardError => e
    Result.new(success: false, output: stdout_data, error: e.message, exit_code: nil, exit_signal: nil)
  end

  def target_user
    @target_node.effective_ssh_user.presence || @ssh_config[:user]
  end

  def target_options
    ssh_options.merge(port: @target_node.effective_ssh_port)
  end

  def ssh_host
    @target_node.ip || @target_node.hostname
  end

  def ssh_options
    options = {
      keys: @ssh_config[:keys],
      key_data: @ssh_config[:key_data],
      password: @ssh_config[:password],
            timeout: @ssh_config[:timeout],
            non_interactive: true
          }

          if @ssh_config[:verify_host_key]
      options[:verify_host_key] = @ssh_config[:verify_host_key]
          end

    options.compact
  end

  def build_ssh_config(config)
    {
      user: config[:user] || default_ssh_user,
      keys: Array(config[:keys] || default_ssh_keys),
      key_data: Array(config[:key_data] || @target_node.effective_ssh_key.presence),
      password: config[:password] || @target_node.effective_sudo_credential.presence,
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
