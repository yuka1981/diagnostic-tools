class AddCurrentPhaseToBenchmarkRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :benchmark_runs, :current_phase, :string
  end
end
