# frozen_string_literal: true

class BmcInventory < ApplicationRecord
  belongs_to :node

  enum :collection_method, { redfish: 0, ipmi: 1 }

  validates :captured_at, presence: true

  scope :latest_for, ->(node_id) { where(node_id: node_id).order(captured_at: :desc).first }
end
