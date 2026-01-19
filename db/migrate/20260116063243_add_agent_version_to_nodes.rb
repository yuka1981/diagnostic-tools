class AddAgentVersionToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :agent_version, :string
  end
end
