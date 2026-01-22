# frozen_string_literal: true

class SshSetting < ApplicationRecord
  DEFAULT_AGENT_PATH = "/usr/local/bin/hpc-agent"

  validates :bastion_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_blank: true

  def self.current
    first_or_create!(bastion_port: 22, default_agent_path: DEFAULT_AGENT_PATH)
  end
end
