# frozen_string_literal: true

class AddRoomHierarchy < ActiveRecord::Migration[7.2]
  def up
    # Drop orphaned rooms table
    drop_table :rooms if table_exists?(:rooms)

    # Create new rooms table with full schema
    create_table :rooms do |t|
      t.references :site, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.decimal :floor_area_sqm, precision: 10, scale: 2
      t.decimal :power_capacity_kw, precision: 10, scale: 2
      t.decimal :cooling_capacity_kw, precision: 10, scale: 2
      t.integer :max_rack_count
      t.integer :floor_number
      t.string :building_wing
      t.string :grid_coordinates
      t.timestamps
    end

    add_index :rooms, [ :site_id, :name ], unique: true

    # Add room_id to racks (nullable initially)
    add_reference :racks, :room, foreign_key: true

    # Data migration: create default room per site, reassign racks
    Site.find_each do |site|
      room = Room.create!(
        site: site,
        name: "Default Room",
        description: "Auto-created during migration"
      )
      ServerRack.where(site_id: site.id).update_all(room_id: room.id)
    end

    # Finalize: make room_id required, remove site_id
    change_column_null :racks, :room_id, false
    remove_index :racks, [ :site_id, :name ]
    remove_index :racks, [ :site_id, :facility_id ]
    remove_index :racks, :site_id
    remove_foreign_key :racks, :sites
    remove_column :racks, :site_id

    # Add new unique indexes scoped to room
    add_index :racks, [ :room_id, :name ], unique: true
    add_index :racks, [ :room_id, :facility_id ], unique: true, where: "facility_id IS NOT NULL"
  end

  def down
    # Add site_id back
    add_reference :racks, :site, foreign_key: true

    # Restore site_id from room's site
    ServerRack.includes(:room).find_each do |rack|
      rack.update_column(:site_id, rack.room.site_id)
    end

    # Make site_id required
    change_column_null :racks, :site_id, false

    # Remove room_id
    remove_index :racks, [ :room_id, :name ]
    remove_index :racks, [ :room_id, :facility_id ]
    remove_foreign_key :racks, :rooms
    remove_column :racks, :room_id

    # Restore original indexes
    add_index :racks, [ :site_id, :name ], unique: true
    add_index :racks, [ :site_id, :facility_id ], unique: true, where: "facility_id IS NOT NULL"
    add_index :racks, :site_id

    # Delete auto-created rooms and drop table
    Room.where(name: "Default Room", description: "Auto-created during migration").destroy_all
    drop_table :rooms
  end
end
