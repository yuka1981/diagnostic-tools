# frozen_string_literal: true

class CreateMlcBaselines < ActiveRecord::Migration[7.2]
  def change
    create_table :mlc_baselines do |t|
      t.references :node, null: false, foreign_key: true
      t.references :benchmark_run, null: false, foreign_key: true
      t.string :metric_type, null: false
      t.float :value, null: false

      t.timestamps
    end

    add_index :mlc_baselines, [ :node_id, :metric_type ], unique: true
  end
end
