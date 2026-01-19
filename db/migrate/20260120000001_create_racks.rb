# frozen_string_literal: true

class CreateRacks < ActiveRecord::Migration[7.2]
  def change
    create_table :racks do |t|
      t.references :room, foreign_key: true
      t.string :name, null: false
      t.integer :u_height, default: 42, null: false
      t.integer :width, default: 19, null: false
      t.text :notes

      t.timestamps
    end

    add_index :racks, [ :room_id, :name ], unique: true
  end
end
