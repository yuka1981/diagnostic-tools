# frozen_string_literal: true

require "net/ssh"

module Ansible
  class ExecutorService
    Result = Struct.new(:success, :output, :error, keyword_init: true) do
      def success?
        success
      end
    end

    # Simple struct containing only the fields needed for admin node SSH connection
    AdminNode = Struct.new(:host, :user, :port, keyword_init: true)

    def initialize(admin_config:, playbook:, extra_vars: {})
      @admin_config = admin_config
      @playbook = playbook
      @extra_vars = extra_vars
    end

    def call
      ssh_result = execute_on_admin_node(build_command)

      if ssh_result.success?
        Result.new(success: true, output: ssh_result.output)
      else
        Result.new(success: false, error: ssh_result.error || ssh_result.output)
      end
    rescue StandardError => e
      Result.new(success: false, error: "Ansible execution failed: #{e.message}")
    end

    private

    def build_command
      playbooks_path = @admin_config[:playbooks_path] || "/opt/ansible"
      extra_vars_json = @extra_vars.to_json.gsub("'", "'\\''")

      <<~CMD.squish
        cd #{Shellwords.escape(playbooks_path)} &&
        ansible-playbook
        playbooks/#{Shellwords.escape(@playbook)}
        --extra-vars '#{extra_vars_json}'
        -v
      CMD
    end

    def execute_on_admin_node(command)
      admin_node = build_admin_node
      ssh_executor = SshAdminExecutor.new(admin_node)
      ssh_executor.execute(command)
    end

    def build_admin_node
      AdminNode.new(
        host: @admin_config[:host],
        user: @admin_config[:user],
        port: @admin_config[:port] || 22
      )
    end

    # Standalone SSH executor for admin node using composition
    # Uses Net::SSH directly for admin node connections
    class SshAdminExecutor
      SshResult = Struct.new(:success, :output, :error, :exit_code, :exit_signal, keyword_init: true) do
        def success?
          success
        end
      end

      DEFAULT_TIMEOUT = 30

      def initialize(admin_node, ssh_config: {})
        @admin_node = admin_node
        @ssh_config = build_ssh_config(ssh_config)
      end

      def execute(command)
        Net::SSH.start(@admin_node.host, ssh_user, ssh_options) do |session|
          execute_on_session(session, command)
        end
      rescue StandardError => e
        SshResult.new(success: false, output: "", error: e.message, exit_code: nil, exit_signal: nil)
      end

      private

      def ssh_user
        @admin_node.user || @ssh_config[:user]
      end

      def ssh_options
        options = {
          port: @admin_node.port,
          keys: @ssh_config[:keys],
          timeout: @ssh_config[:timeout],
          non_interactive: true
        }

        options[:verify_host_key] = @ssh_config[:verify_host_key] if @ssh_config[:verify_host_key]

        options.compact
      end

      def execute_on_session(session, cmd)
        stdout_data = ""
        stderr_data = ""
        exit_code = nil
        exit_signal = nil

        channel = session.open_channel do |ch|
          ch.exec(cmd) do |c, success|
            raise "Could not execute command" unless success

            ch.on_data { |_, data| stdout_data += data.to_s }
            ch.on_extended_data { |_, _type, data| stderr_data += data.to_s }
            c.on_request("exit-status") { |_, data| exit_code = data.read_long }
            c.on_request("exit-signal") { |_, data| exit_signal = data.read_long }
          end
        end
        channel.wait

        success = exit_code == 0 && exit_signal.nil?
        SshResult.new(success: success, output: stdout_data, error: stderr_data, exit_code: exit_code, exit_signal: exit_signal)
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
    end
  end
end
