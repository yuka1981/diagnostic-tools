class AddDmiInfoToNodeStates < ActiveRecord::Migration[7.2]
  def change
    add_column :node_states, :dmi_info, :jsonb, default: {}
  end
end

