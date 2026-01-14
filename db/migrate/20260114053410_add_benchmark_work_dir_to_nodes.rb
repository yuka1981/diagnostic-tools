class AddBenchmarkWorkDirToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :benchmark_work_dir, :string
  end
end
