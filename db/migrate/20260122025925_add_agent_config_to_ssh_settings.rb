# frozen_string_literal: true

class AddAgentConfigToSshSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ssh_settings, :default_agent_path, :string, default: "/usr/local/bin/qis-agent"
  end
end
