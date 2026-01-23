# frozen_string_literal: true

class SshSetting < ApplicationRecord
  DEFAULT_AGENT_PATH = "/usr/local/bin/hpc-agent"

  validates :bastion_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_blank: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_blank: true
  validates :timeout, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 300 }, allow_blank: true

  def self.current
    first_or_create!(
      bastion_port: 22,
      ssh_port: 22,
      timeout: 30,
      verify_host_key: false,
      default_agent_path: DEFAULT_AGENT_PATH
    )
  end
end
