# frozen_string_literal: true

module Ansible
  class ExecutorService
    Result = Struct.new(:success, :output, :error, keyword_init: true) do
      def success?
        success
      end
    end

    # Simple struct-like class to represent an admin node for SSH connection
    AdminNode = Struct.new(:hostname, :ip, :ssh_user, :ssh_port, :ssh_connect_method, keyword_init: true) do
      def direct?
        ssh_connect_method == :direct
      end

      # Required by SshExecutionService
      def jump_host
        nil
      end

      def jump_user
        nil
      end

      def jump_port
        nil
      end

      def ssh_key
        nil
      end

      def sudo_credential
        nil
      end
    end

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
      ssh_service = SshAdminExecutor.new(admin_node)
      ssh_service.execute(command)
    end

    def build_admin_node
      AdminNode.new(
        hostname: @admin_config[:host],
        ip: @admin_config[:host],
        ssh_user: @admin_config[:user],
        ssh_port: @admin_config[:port] || 22,
        ssh_connect_method: :direct
      )
    end

    # Lightweight SSH executor for admin node
    class SshAdminExecutor < SshExecutionService
      def initialize(admin_node)
        super(admin_node)
      end

      def execute(command)
        execute_ssh_command(command)
      end

      private

      def direct_connection_required?
        true
      end
    end
  end
end
