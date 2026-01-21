class AddImageUrlToServerProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :server_products, :image_url, :string
  end
end
