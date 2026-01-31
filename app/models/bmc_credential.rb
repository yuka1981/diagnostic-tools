# frozen_string_literal: true

class BmcCredential < ApplicationRecord
  belongs_to :node, optional: true

  encrypts :password

  enum :protocol, { auto: 0, redfish: 1, ipmi: 2 }

  validates :bmc_address, presence: true
  validates :username, presence: true
  validates :password, presence: true

  def self.global_default
    find_by(is_global_default: true)
  end

  def self.for_node(node)
    find_by(node: node) || global_default
  end
end
