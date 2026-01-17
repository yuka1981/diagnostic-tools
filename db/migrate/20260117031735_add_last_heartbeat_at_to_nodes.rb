class AddLastHeartbeatAtToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :last_heartbeat_at, :datetime
  end
end
