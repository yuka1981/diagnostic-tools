class CreateArtifactIndices < ActiveRecord::Migration[7.2]
  def change
    create_table :artifact_indices do |t|
      t.references :benchmark_run, null: false, foreign_key: true
      t.string :path
      t.string :file_type
      t.bigint :size

      t.timestamps
    end
  end
end
