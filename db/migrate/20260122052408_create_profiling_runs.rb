# frozen_string_literal: true

class CreateProfilingRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :profiling_runs do |t|
      t.uuid :uuid, default: -> { "gen_random_uuid()" }, null: false
      t.references :node, null: false, foreign_key: true
      t.references :profiling_recipe, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :status, default: 0, null: false
      t.string :subcommand, null: false
      t.jsonb :options, default: {}
      t.jsonb :metrics, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.text :log_content
      t.text :error_message
      t.string :artifact_path

      t.timestamps
    end

    add_index :profiling_runs, :uuid, unique: true
    add_index :profiling_runs, :status
    add_index :profiling_runs, [ :node_id, :created_at ], order: { created_at: :desc }
  end
end
