# frozen_string_literal: true

class AddRowToEquipmentRacks < ActiveRecord::Migration[7.2]
  def change
    add_column :racks, :row, :string
    add_index :racks, [ :room_id, :row, :name ]
  end
end
