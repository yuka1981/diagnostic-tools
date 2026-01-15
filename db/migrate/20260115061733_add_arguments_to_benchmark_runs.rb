class AddArgumentsToBenchmarkRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :benchmark_runs, :arguments, :jsonb, default: {}
  end
end
