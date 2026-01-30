class RemoveAgentAndSshIntegration < ActiveRecord::Migration[7.2]
  def up
    # Drop agent/SSH tables
    drop_table :agent_events, if_exists: true
    drop_table :agent_binaries, if_exists: true
    drop_table :agent_releases, if_exists: true
    drop_table :ssh_settings, if_exists: true

    # Remove agent columns from nodes
    remove_column :nodes, :agent_path, if_exists: true
    remove_column :nodes, :agent_version, if_exists: true
    remove_column :nodes, :agent_status, if_exists: true
    remove_column :nodes, :last_heartbeat_at, if_exists: true

    # Remove SSH columns from nodes
    remove_column :nodes, :ssh_port, if_exists: true
    remove_column :nodes, :ssh_user, if_exists: true
    remove_column :nodes, :ssh_key, if_exists: true
    remove_column :nodes, :ssh_password, if_exists: true
    remove_column :nodes, :ssh_connect_method, if_exists: true
    remove_column :nodes, :sudo_credential, if_exists: true
    remove_column :nodes, :benchmark_work_dir, if_exists: true

    # Remove SSH override flags from nodes
    remove_column :nodes, :ssh_user_override, if_exists: true
    remove_column :nodes, :ssh_port_override, if_exists: true
    remove_column :nodes, :ssh_key_override, if_exists: true
    remove_column :nodes, :ssh_password_override, if_exists: true
    remove_column :nodes, :sudo_credential_override, if_exists: true
    remove_column :nodes, :ssh_connect_method_override, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
