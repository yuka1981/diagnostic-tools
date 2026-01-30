# frozen_string_literal: true

class InventoryDiscrepancy < ApplicationRecord
  belongs_to :node

  enum :severity, { info: 0, warning: 1, critical: 2 }

  validates :field_path, presence: true

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  def resolved?
    resolved_at.present?
  end

  def resolve!(note: nil)
    update!(resolved_at: Time.current, resolution_note: note)
  end
end
