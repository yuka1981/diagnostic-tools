class AddSshConnectMethodToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :ssh_connect_method, :integer
  end
end
