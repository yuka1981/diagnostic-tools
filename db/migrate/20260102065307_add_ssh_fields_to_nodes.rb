class AddSshFieldsToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :ssh_port, :integer, default: 22, null: false
    add_column :nodes, :ssh_user, :string
  end
end
