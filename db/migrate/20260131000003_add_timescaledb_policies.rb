class AddTimescaledbPolicies < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    execute <<~SQL
      CREATE MATERIALIZED VIEW bmc_sensor_readings_hourly
      WITH (timescaledb.continuous) AS
      SELECT
        node_id,
        sensor_type,
        sensor_name,
        time_bucket('1 hour', recorded_at) AS bucket,
        AVG(value) AS avg_value,
        MIN(value) AS min_value,
        MAX(value) AS max_value,
        unit
      FROM bmc_sensor_readings
      GROUP BY node_id, sensor_type, sensor_name, time_bucket('1 hour', recorded_at), unit;
    SQL

    execute <<~SQL
      SELECT add_continuous_aggregate_policy('bmc_sensor_readings_hourly',
        start_offset => INTERVAL '3 hours',
        end_offset => INTERVAL '1 hour',
        schedule_interval => INTERVAL '1 hour');
    SQL

    execute "SELECT add_retention_policy('bmc_sensor_readings', INTERVAL '7 days');"
    execute "SELECT add_retention_policy('bmc_sensor_readings_hourly', INTERVAL '90 days');"
  end

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS bmc_sensor_readings_hourly CASCADE;"
    execute "SELECT remove_retention_policy('bmc_sensor_readings', if_exists => true);"
  end
end
