class AddServerUrlToSshSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ssh_settings, :server_url, :string
  end
end
