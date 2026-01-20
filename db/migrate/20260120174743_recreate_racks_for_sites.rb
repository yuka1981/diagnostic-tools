# frozen_string_literal: true

class RecreateRacksForSites < ActiveRecord::Migration[7.2]
  def change
    # Remove foreign key from nodes table first
    remove_foreign_key :nodes, :racks, if_exists: true

    # Clear existing rack_id values on nodes (old rack references are no longer valid)
    execute "UPDATE nodes SET rack_id = NULL WHERE rack_id IS NOT NULL"

    # Remove old racks table that was tied to rooms
    drop_table :racks, if_exists: true

    # Create new racks table tied to sites
    create_table :racks do |t|
      t.references :site, null: false, foreign_key: true
      t.string :name, null: false, limit: 255
      t.string :facility_id, limit: 255
      t.string :asset_tag, limit: 255
      t.integer :u_height, null: false, default: 42
      t.integer :width_mm
      t.integer :depth_mm
      t.integer :max_weight_kg
      t.integer :status, null: false, default: 0
      t.boolean :desc_units, null: false, default: false

      t.timestamps
    end

    add_index :racks, [ :site_id, :name ], unique: true
    add_index :racks, [ :site_id, :facility_id ], unique: true, where: "facility_id IS NOT NULL"
    add_index :racks, :status

    # Re-add foreign key from nodes to racks
    add_foreign_key :nodes, :racks
  end
end
