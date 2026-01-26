# frozen_string_literal: true

class CreateBmcInventories < ActiveRecord::Migration[7.2]
  def change
    create_table :bmc_inventories do |t|
      t.references :node, foreign_key: true, null: false
      t.jsonb :processors, default: []
      t.jsonb :memory, default: []
      t.jsonb :storage, default: []
      t.jsonb :network, default: []
      t.jsonb :infiniband, default: []
      t.jsonb :bios, default: {}
      t.jsonb :bmc_info, default: {}
      t.integer :collection_method # 0=redfish, 1=ipmi
      t.datetime :captured_at, null: false
      t.timestamps
    end

    add_index :bmc_inventories, :captured_at
  end
end
