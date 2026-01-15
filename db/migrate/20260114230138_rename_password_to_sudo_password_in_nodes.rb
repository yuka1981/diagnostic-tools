# frozen_string_literal: true

class RenamePasswordToSudoPasswordInNodes < ActiveRecord::Migration[7.2]
  def change
    rename_column :nodes, :password, :sudo_credential
  end
end
