# frozen_string_literal: true

class BmcInventory < ApplicationRecord
  # Associations
  belongs_to :node

  # Enums
  enum :collection_method, { redfish: 0, ipmi: 1 }

  # Validations
  validates :captured_at, presence: true

  # Scopes
  scope :for_node, ->(node_or_id) { where(node: node_or_id) }
  scope :latest, lambda {
    subquery = select("DISTINCT ON (node_id) *")
                 .order(:node_id, captured_at: :desc)
    from(subquery, :bmc_inventories)
  }
end
