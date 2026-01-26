# frozen_string_literal: true

class CreateInventoryDiscrepancies < ActiveRecord::Migration[7.2]
  def change
    create_table :inventory_discrepancies do |t|
      t.references :node, foreign_key: true, null: false
      t.string :field_path, null: false
      t.string :inband_value
      t.string :bmc_value
      t.integer :severity, default: 0 # 0=info, 1=warning, 2=critical
      t.datetime :resolved_at
      t.text :resolution_note
      t.timestamps
    end
    add_index :inventory_discrepancies, [ :node_id, :resolved_at ]
  end
end
