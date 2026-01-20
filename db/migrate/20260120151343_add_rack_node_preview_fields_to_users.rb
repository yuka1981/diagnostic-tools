class AddRackNodePreviewFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :rack_node_preview_fields, :string, array: true, default: %w[cpu ram storage network]
  end
end
