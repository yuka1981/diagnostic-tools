# frozen_string_literal: true

class BmcCredential < ApplicationRecord
  # Associations
  belongs_to :node, optional: true

  # Encryption
  encrypts :username
  encrypts :password

  # Enums
  enum :protocol, { auto: 0, redfish: 1, ipmi: 2 }, default: :auto

  # Validations
  validates :bmc_address, presence: true
  validates :username, presence: true
  validates :password, presence: true
  validates :node_id, uniqueness: true, allow_nil: true
  validates :is_global_default, uniqueness: { message: "has already been taken" }, if: :is_global_default?
  validate :global_default_must_have_nil_node

  # Scopes
  scope :global_default, -> { where(is_global_default: true) }

  # Class methods
  def self.global_default_record
    global_default.first
  end

  private

  def global_default_must_have_nil_node
    return unless is_global_default? && node_id.present?

    errors.add(:node_id, "must be nil for global default credential")
  end
end
