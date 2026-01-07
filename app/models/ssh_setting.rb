# frozen_string_literal: true

class SshSetting < ApplicationRecord
  validates :bastion_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_blank: true

  def self.current
    first_or_create!(bastion_port: 22)
  end
end
