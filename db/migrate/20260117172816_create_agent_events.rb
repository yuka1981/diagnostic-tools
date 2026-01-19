class CreateAgentEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_events do |t|
      t.references :node, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :agent_release, null: true, foreign_key: true

      t.string :operation, null: false
      t.string :status, null: false, default: "pending"
      t.string :from_version
      t.string :to_version
      t.text :error_message
      t.jsonb :error_details, default: {}
      t.boolean :forced, default: false

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :agent_events, :operation
    add_index :agent_events, :status
    add_index :agent_events, :created_at
  end
end
