class AddAgentPathToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :agent_path, :string
  end
end
