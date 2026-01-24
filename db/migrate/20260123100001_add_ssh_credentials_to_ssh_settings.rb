class AddSshCredentialsToSshSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ssh_settings, :ssh_user, :string
    add_column :ssh_settings, :ssh_port, :integer, default: 22
    add_column :ssh_settings, :ssh_key, :text
    add_column :ssh_settings, :ssh_password, :string
    add_column :ssh_settings, :sudo_credential, :string
    add_column :ssh_settings, :timeout, :integer, default: 30
    add_column :ssh_settings, :verify_host_key, :boolean, default: false
  end
end
