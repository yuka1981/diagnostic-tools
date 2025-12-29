# frozen_string_literal: true

class CreateNodeStates < ActiveRecord::Migration[7.2]
  def change
    create_table :node_states do |t|
      t.references :node, null: false, foreign_key: true
      t.jsonb :cpu_info, default: {}
      t.jsonb :mem_info, default: {}
      t.jsonb :disk_info, default: []
      t.jsonb :net_info, default: []
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :node_states, [ :node_id, :captured_at ], order: { captured_at: :desc }
    add_index :node_states, :captured_at
  end
end
