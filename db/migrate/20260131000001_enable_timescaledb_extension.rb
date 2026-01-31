class EnableTimescaledbExtension < ActiveRecord::Migration[7.2]
  def change
    enable_extension "timescaledb" unless extension_enabled?("timescaledb")
  end
end
