class AddBmcSettingsToSshSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ssh_settings, :bmc_sensor_polling_interval, :integer, default: 5
    add_column :ssh_settings, :bmc_collection_enabled, :boolean, default: false
    add_column :ssh_settings, :prometheus_pushgateway_url, :string
    add_column :ssh_settings, :prometheus_url, :string
  end
end
