class AddFieldsToBenchmarkRecipes < ActiveRecord::Migration[7.2]
  def change
    add_column :benchmark_recipes, :slug, :string
    add_index :benchmark_recipes, :slug, unique: true
    add_column :benchmark_recipes, :command, :string
    add_column :benchmark_recipes, :description, :text
    add_column :benchmark_recipes, :timeout_seconds, :integer, default: 3600
    add_column :benchmark_recipes, :status, :integer, default: 0, null: false

    # Backfill existing records with slug and command based on name
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE benchmark_recipes
          SET slug = LOWER(REPLACE(name || '-' || version, ' ', '-')),
              command = name
          WHERE slug IS NULL
        SQL
      end
    end
  end
end
