# frozen_string_literal: true

class InventoryDiscrepancy < ApplicationRecord
  # Associations
  belongs_to :node

  # Enums
  enum :severity, { info: 0, warning: 1, critical: 2 }, default: :info

  # Validations
  validates :field_path, presence: true

  # Scopes
  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  # Instance methods
  def resolved?
    resolved_at.present?
  end

  def resolve!(note = nil)
    update!(resolved_at: Time.current, resolution_note: note)
  end
end
