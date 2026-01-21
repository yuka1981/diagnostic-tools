class CreateServerProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :server_products do |t|
      t.string :name, null: false, limit: 255
      t.string :product_series, limit: 100
      t.string :form_factor, limit: 20
      t.integer :rack_height, default: 1
      t.string :qct_product_url, limit: 500

      # CPU specs
      t.string :cpu_generations, array: true, default: []
      t.integer :socket_count
      t.integer :max_tdp_watts

      # Memory specs
      t.integer :max_memory_gb
      t.integer :dimm_slots
      t.string :memory_types, array: true, default: []
      t.integer :max_memory_speed_mhz

      # Storage specs
      t.jsonb :drive_bays, default: []

      # PCIe specs
      t.jsonb :pcie_slots, default: []

      # Other specs
      t.jsonb :power_supply_options, default: []
      t.boolean :gpu_support, default: false
      t.jsonb :network_options, default: []

      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :server_products, :name, unique: true
    add_index :server_products, :product_series
    add_index :server_products, :form_factor
  end
end
