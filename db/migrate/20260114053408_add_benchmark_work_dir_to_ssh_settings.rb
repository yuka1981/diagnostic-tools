class AddBenchmarkWorkDirToSshSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ssh_settings, :benchmark_work_dir, :string
  end
end
