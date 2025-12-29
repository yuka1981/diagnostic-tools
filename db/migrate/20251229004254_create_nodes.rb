# frozen_string_literal: true

class CreateNodes < ActiveRecord::Migration[7.2]
  def change
    create_table :nodes do |t|
      t.string :hostname, null: false
      t.string :ip
      t.integer :role, default: 0, null: false
      t.string :arch
      t.integer :source, default: 0, null: false
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :nodes, :hostname, unique: true
    add_index :nodes, :role
    add_index :nodes, :source
  end
end
