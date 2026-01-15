class AddLogContentToBenchmarkRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :benchmark_runs, :log_content, :text
  end
end
