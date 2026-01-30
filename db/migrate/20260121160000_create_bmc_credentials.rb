class CreateBmcCredentials < ActiveRecord::Migration[7.2]
  def change
    create_table :bmc_credentials do |t|
      t.bigint :node_id
      t.string :bmc_address, null: false
      t.string :username, null: false
      t.string :password, null: false
      t.integer :protocol, default: 0
      t.integer :port
      t.boolean :verify_ssl, default: true
      t.boolean :is_global_default, default: false
      t.timestamps
    end

    add_index :bmc_credentials, :is_global_default, unique: true, where: "(is_global_default = true)"
    add_index :bmc_credentials, :node_id, unique: true, where: "(node_id IS NOT NULL)"
    add_foreign_key :bmc_credentials, :nodes
  end
end
