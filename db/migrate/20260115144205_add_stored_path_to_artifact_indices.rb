class AddStoredPathToArtifactIndices < ActiveRecord::Migration[7.2]
  def change
    add_column :artifact_indices, :stored_path, :string
  end
end
