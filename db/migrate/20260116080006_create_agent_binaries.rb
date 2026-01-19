class CreateAgentBinaries < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_binaries do |t|
      t.references :agent_release, null: false, foreign_key: true
      t.string :arch, null: false
      t.string :checksum

      t.timestamps
    end

    add_index :agent_binaries, %i[agent_release_id arch], unique: true
  end
end
