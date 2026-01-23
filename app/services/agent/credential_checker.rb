# frozen_string_literal: true

module Agent
  # Determines which credential fields are needed for agent operations.
  # Used to show modal only when credentials are actually missing.
  class CredentialChecker
    def initialize(node, operation:)
      @node = node
      @operation = operation # :install, :update, :uninstall
    end

    def needs_ssh_password?
      # SSH key available? No password needed
      return false if @node.effective_ssh_key.present?
      return false if SshConfig.ssh_key.present?

      # Has stored password? No prompt needed
      return false if @node.effective_ssh_password.present?

      true
    end

    def needs_sudo_credential?
      # Root user? No sudo needed
      ssh_user = @node.effective_ssh_user.presence || SshConfig.user || "root"
      return false if ssh_user == "root"

      # Has stored credential? No prompt needed
      return false if @node.effective_sudo_credential.present?

      true
    end

    def needs_api_key?
      return false unless @operation == :install

      @node.api_key_id.nil?
    end

    def needs_server_url?
      return false unless @operation == :install

      SshSetting.current.server_url.blank?
    end

    def needs_modal?
      needs_ssh_password? || needs_sudo_credential? ||
        needs_api_key? || needs_server_url?
    end

    def required_fields
      {
        ssh_password: needs_ssh_password?,
        sudo_password: needs_sudo_credential?,
        api_key: needs_api_key?,
        server_url: needs_server_url?
      }
    end
  end
end
