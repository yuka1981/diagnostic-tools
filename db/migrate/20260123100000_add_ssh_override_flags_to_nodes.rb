class AddSshOverrideFlagsToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :ssh_user_override, :boolean, default: false
    add_column :nodes, :ssh_port_override, :boolean, default: false
    add_column :nodes, :ssh_key_override, :boolean, default: false
    add_column :nodes, :ssh_password_override, :boolean, default: false
    add_column :nodes, :sudo_credential_override, :boolean, default: false
    add_column :nodes, :ssh_connect_method_override, :boolean, default: false
  end
end
