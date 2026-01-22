# frozen_string_literal: true

class CreateProfilingArtifacts < ActiveRecord::Migration[7.2]
  def change
    create_table :profiling_artifacts do |t|
      t.references :profiling_run, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :file_type
      t.string :file_path
      t.bigint :file_size

      t.timestamps
    end

    add_index :profiling_artifacts, [:profiling_run_id, :filename], unique: true
  end
end
