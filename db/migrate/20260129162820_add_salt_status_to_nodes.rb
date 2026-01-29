class AddSaltStatusToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :salt_status, :integer, default: 0, null: false
    add_index :nodes, :salt_status
  end
end
