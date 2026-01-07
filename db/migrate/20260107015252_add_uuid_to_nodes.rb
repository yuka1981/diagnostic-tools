class AddUuidToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :uuid, :string
    add_index :nodes, :uuid
  end
end
