class AddApiTokenToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :api_token, :string
  end
end
