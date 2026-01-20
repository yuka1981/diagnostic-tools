# frozen_string_literal: true

class CreateSites < ActiveRecord::Migration[7.2]
  def change
    create_table :sites do |t|
      t.string :name, null: false, limit: 255
      t.text :description

      t.timestamps
    end

    add_index :sites, :name, unique: true
  end
end
