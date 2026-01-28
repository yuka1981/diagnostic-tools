class CreateMlcInstallationNodes < ActiveRecord::Migration[7.2]
  def change
    create_table :mlc_installation_nodes do |t|
      t.references :mlc_installation, null: false, foreign_key: true
      t.references :node, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :step_current, default: 0
      t.integer :step_total, default: 7
      t.string :step_name
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :mlc_installation_nodes, [ :mlc_installation_id, :node_id ], unique: true
  end
end
