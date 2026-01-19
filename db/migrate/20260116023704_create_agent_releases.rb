class CreateAgentReleases < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_releases do |t|
      t.string :version, null: false
      t.string :checksum
      t.text :release_notes
      t.integer :status, default: 0, null: false

      t.timestamps
    end
    add_index :agent_releases, :version, unique: true
    add_index :agent_releases, :status
  end
end
