class CreateRooms < ActiveRecord::Migration[7.2]
  def change
    create_table :rooms do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    add_index :rooms, :name, unique: true
  end
end
