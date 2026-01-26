# frozen_string_literal: true

class CreateBmcCredentials < ActiveRecord::Migration[7.2]
  def change
    create_table :bmc_credentials do |t|
      t.references :node, foreign_key: true, null: true, index: false # nil = global default
      t.string :bmc_address, null: false
      t.string :username, null: false
      t.string :password, null: false
      t.integer :protocol, default: 0 # 0=auto, 1=redfish, 2=ipmi
      t.integer :port
      t.boolean :verify_ssl, default: true
      t.boolean :is_global_default, default: false

      t.timestamps
    end

    add_index :bmc_credentials, :node_id, unique: true, where: "node_id IS NOT NULL"
    add_index :bmc_credentials, :is_global_default, unique: true, where: "is_global_default = true"
  end
end
