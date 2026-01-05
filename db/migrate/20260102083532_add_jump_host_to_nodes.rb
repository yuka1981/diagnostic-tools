class AddJumpHostToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :jump_host, :string
    add_column :nodes, :jump_user, :string
    add_column :nodes, :jump_port, :integer
  end
end
