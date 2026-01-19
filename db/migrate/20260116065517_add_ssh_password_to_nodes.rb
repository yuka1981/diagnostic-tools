class AddSshPasswordToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :ssh_password, :string
  end
end
