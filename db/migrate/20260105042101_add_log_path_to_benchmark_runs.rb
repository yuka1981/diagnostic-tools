class AddLogPathToBenchmarkRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :benchmark_runs, :log_path, :string
  end
end
