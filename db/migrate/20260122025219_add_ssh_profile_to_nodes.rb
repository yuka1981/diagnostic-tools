# frozen_string_literal: true

class AddSshProfileToNodes < ActiveRecord::Migration[7.2]
  def change
    add_reference :nodes, :ssh_profile, null: true, foreign_key: true
    add_column :nodes, :ssh_profile_override, :boolean, default: false, null: false
  end
end
