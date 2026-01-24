# frozen_string_literal: true

# Migrates existing node SSH settings by enabling override flags
# for nodes that have custom values set. This preserves the behavior
# of existing configurations after the SSH consolidation.
class SshOverrideMigrationService
  def self.migrate_existing_nodes
    Node.find_each do |node|
      updates = {}

      # Enable override if custom user is set
      updates[:ssh_user_override] = true if node.ssh_user.present?

      # Enable override if port differs from default (22)
      updates[:ssh_port_override] = true if node.ssh_port.present? && node.ssh_port != 22

      # Enable override if custom key is set
      updates[:ssh_key_override] = true if node.ssh_key.present?

      # Enable override if custom password is set
      updates[:ssh_password_override] = true if node.ssh_password.present?

      # Enable override if custom sudo credential is set
      updates[:sudo_credential_override] = true if node.sudo_credential.present?

      # Enable override if connection method is not the default (global_bastion)
      updates[:ssh_connect_method_override] = true if node.ssh_connect_method == "direct"

      node.update!(updates) if updates.any?
    end
  end
end
