# frozen_string_literal: true

class SshProfile < ApplicationRecord
  # Associations
  has_many :nodes, dependent: :nullify

  # Enums (matches Node model for consistency)
  enum :ssh_connect_method, { global_bastion: 0, custom_bastion: 1, direct: 2 }, default: :global_bastion

  # Validations
  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :ssh_connect_method, presence: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
  validates :ssh_user, length: { maximum: 255 }
  validates :jump_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_nil: true

  # Instance methods
  def display_connection_method
    ssh_connect_method.to_s.titleize
  end
end
