class AddServerProductToNodes < ActiveRecord::Migration[7.2]
  def change
    add_reference :nodes, :server_product, null: true, foreign_key: true
  end
end
