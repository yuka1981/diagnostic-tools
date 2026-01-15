class AddApiKeyToNodes < ActiveRecord::Migration[7.2]
  def change
    add_reference :nodes, :api_key, null: true, foreign_key: true
  end
end
