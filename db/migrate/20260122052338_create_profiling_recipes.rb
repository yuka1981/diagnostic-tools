# frozen_string_literal: true

class CreateProfilingRecipes < ActiveRecord::Migration[7.2]
  def change
    create_table :profiling_recipes do |t|
      t.string :name, null: false, limit: 100
      t.string :slug, null: false
      t.text :description
      t.string :tool, null: false, default: "perfspect"
      t.string :subcommand, null: false
      t.string :module_name, null: false, default: "perfspect/3.13.0"
      t.jsonb :default_options, default: {}
      t.integer :timeout_seconds, default: 300
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :profiling_recipes, :slug, unique: true
    add_index :profiling_recipes, :tool
    add_index :profiling_recipes, :status
  end
end
