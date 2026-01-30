class CreateBmcInventories < ActiveRecord::Migration[7.2]
  def change
    create_table :bmc_inventories do |t|
      t.bigint :node_id, null: false
      t.jsonb :processors, default: []
      t.jsonb :memory, default: []
      t.jsonb :storage, default: []
      t.jsonb :network, default: []
      t.jsonb :infiniband, default: []
      t.jsonb :bios, default: {}
      t.jsonb :bmc_info, default: {}
      t.integer :collection_method
      t.datetime :captured_at, null: false
      t.timestamps
    end

    add_index :bmc_inventories, :captured_at
    add_index :bmc_inventories, :node_id
    add_foreign_key :bmc_inventories, :nodes
  end
end
