# frozen_string_literal: true

class CreateBenchmarkRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :benchmark_runs do |t|
      t.references :node, null: false, foreign_key: true
      t.references :benchmark_recipe, null: false, foreign_key: true
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :status, null: false, default: 0
      t.jsonb :metrics, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :benchmark_runs, :status
    add_index :benchmark_runs, :started_at
    add_index :benchmark_runs, [ :node_id, :started_at ], order: { started_at: :desc }
  end
end
