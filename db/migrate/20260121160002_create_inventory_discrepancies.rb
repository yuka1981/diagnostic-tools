class CreateInventoryDiscrepancies < ActiveRecord::Migration[7.2]
  def change
    create_table :inventory_discrepancies do |t|
      t.bigint :node_id, null: false
      t.string :field_path, null: false
      t.string :inband_value
      t.string :bmc_value
      t.integer :severity, default: 0
      t.datetime :resolved_at
      t.text :resolution_note
      t.timestamps
    end

    add_index :inventory_discrepancies, [ :node_id, :resolved_at ]
    add_index :inventory_discrepancies, :node_id
    add_foreign_key :inventory_discrepancies, :nodes
  end
end
