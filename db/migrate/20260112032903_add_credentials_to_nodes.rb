class AddCredentialsToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :ssh_key, :text
    add_column :nodes, :password, :string
  end
end
