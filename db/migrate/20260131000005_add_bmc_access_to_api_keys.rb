# frozen_string_literal: true

class AddBmcAccessToApiKeys < ActiveRecord::Migration[7.2]
  def change
    add_column :api_keys, :bmc_access, :boolean, default: false, null: false
  end
end
