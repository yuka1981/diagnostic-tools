# frozen_string_literal: true

class CreateSshProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :ssh_profiles do |t|
      t.string :name, null: false, limit: 255
      t.integer :ssh_connect_method, default: 0, null: false
      t.integer :ssh_port, default: 22, null: false
      t.string :ssh_user, limit: 255
      t.string :ssh_password
      t.text :ssh_key
      t.string :sudo_credential
      t.string :jump_host, limit: 255
      t.string :jump_user, limit: 255
      t.integer :jump_port

      t.timestamps
    end

    add_index :ssh_profiles, :name, unique: true
  end
end
