# frozen_string_literal: true

class AddRackFieldsToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :rack_id, :bigint
    add_column :nodes, :rack_position, :integer
    add_column :nodes, :rack_height, :integer, default: 1
    add_column :nodes, :rack_face, :integer, default: 0
    add_index :nodes, :rack_id
    add_index :nodes, [ :rack_id, :rack_face, :rack_position ]
  end
end
