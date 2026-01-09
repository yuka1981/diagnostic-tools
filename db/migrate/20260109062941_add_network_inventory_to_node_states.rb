class AddNetworkInventoryToNodeStates < ActiveRecord::Migration[7.2]
  def change
    add_column :node_states, :network_inventory, :jsonb
  end
end
