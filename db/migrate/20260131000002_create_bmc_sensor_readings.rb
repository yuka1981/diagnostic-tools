class CreateBmcSensorReadings < ActiveRecord::Migration[7.2]
  def up
    create_table :bmc_sensor_readings, id: false do |t|
      t.bigint :node_id, null: false
      t.string :sensor_type, null: false
      t.string :sensor_name, null: false
      t.float :value, null: false
      t.string :unit, null: false
      t.string :status
      t.timestamptz :recorded_at, null: false
    end

    add_index :bmc_sensor_readings, [:node_id, :recorded_at, :sensor_type],
              name: "idx_sensor_readings_node_time_type"
    add_foreign_key :bmc_sensor_readings, :nodes

    # Convert to TimescaleDB hypertable with 7-day chunks
    execute <<~SQL
      SELECT create_hypertable('bmc_sensor_readings', 'recorded_at',
        chunk_time_interval => INTERVAL '7 days');
    SQL

    # Enable compression on chunks older than 7 days
    execute <<~SQL
      ALTER TABLE bmc_sensor_readings SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'node_id, sensor_type, sensor_name'
      );
    SQL
    execute "SELECT add_compression_policy('bmc_sensor_readings', INTERVAL '7 days');"
  end

  def down
    drop_table :bmc_sensor_readings
  end
end
