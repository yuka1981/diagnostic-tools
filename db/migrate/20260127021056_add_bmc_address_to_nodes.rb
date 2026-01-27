class AddBmcAddressToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :bmc_address, :string
  end
end
