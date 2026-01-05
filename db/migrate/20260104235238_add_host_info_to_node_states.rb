class AddHostInfoToNodeStates < ActiveRecord::Migration[7.2]
  def change
    add_column :node_states, :host_info, :jsonb, default: {}
  end
end
