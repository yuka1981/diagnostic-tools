class AddUuidToBenchmarkRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :benchmark_runs, :uuid, :uuid, default: "gen_random_uuid()", null: false
    add_index :benchmark_runs, :uuid, unique: true
  end
end
