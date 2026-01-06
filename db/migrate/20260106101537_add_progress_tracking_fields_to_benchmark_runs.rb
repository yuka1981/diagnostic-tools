# frozen_string_literal: true

class AddProgressTrackingFieldsToBenchmarkRuns < ActiveRecord::Migration[7.2]
  def up
    add_column :benchmark_runs, :last_heartbeat_at, :datetime
    add_column :benchmark_runs, :current_phase, :string

    remap_status_values_to_progress_states
  end

  def down
    revert_status_values_to_legacy_states

    remove_column :benchmark_runs, :current_phase
    remove_column :benchmark_runs, :last_heartbeat_at
  end

  private

  def remap_status_values_to_progress_states
    execute <<~SQL
      UPDATE benchmark_runs
      SET status = CASE status
        WHEN 0 THEN 0  -- pending
        WHEN 1 THEN 3  -- running -> running (new value)
        WHEN 2 THEN 5  -- success -> success (new value)
        WHEN 3 THEN 6  -- failed  -> failed (new value)
        WHEN 4 THEN 6  -- cancelled -> failed (closest available)
        ELSE status
      END;
    SQL
  end

  def revert_status_values_to_legacy_states
    execute <<~SQL
      UPDATE benchmark_runs
      SET status = CASE status
        WHEN 0 THEN 0  -- pending
        WHEN 1 THEN 0  -- preparing -> pending
        WHEN 2 THEN 1  -- building -> running
        WHEN 3 THEN 1  -- running  -> running
        WHEN 4 THEN 1  -- uploading -> running
        WHEN 5 THEN 2  -- success -> success
        WHEN 6 THEN 3  -- failed  -> failed
        WHEN 7 THEN 4  -- lost    -> cancelled (legacy)
        ELSE status
      END;
    SQL
  end
end
