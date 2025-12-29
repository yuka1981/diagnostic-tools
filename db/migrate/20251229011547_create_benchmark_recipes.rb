# frozen_string_literal: true

class CreateBenchmarkRecipes < ActiveRecord::Migration[7.2]
  def change
    create_table :benchmark_recipes do |t|
      t.string :name, null: false, limit: 100
      t.string :version, null: false, limit: 50
      t.jsonb :default_profile, default: {}

      t.timestamps
    end

    add_index :benchmark_recipes, [ :name, :version ], unique: true
    add_index :benchmark_recipes, :name
  end
end
