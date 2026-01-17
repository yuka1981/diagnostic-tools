class AddAgentStatusToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :agent_status, :string, default: "idle"
  end
end
