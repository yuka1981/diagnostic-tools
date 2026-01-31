# frozen_string_literal: true

class AddCollectionIntervalToBmcCredentials < ActiveRecord::Migration[7.2]
  def change
    add_column :bmc_credentials, :collection_interval, :integer, default: 5
  end
end
