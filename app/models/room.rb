# frozen_string_literal: true

class Room < ApplicationRecord
  # Associations
  # Note: We use EquipmentRack model (to avoid conflict with Rack gem) with foreign_key :room_id
  has_many :equipment_racks, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: true

  # Returns racks grouped by row for room layout visualization
  # Racks without a row are grouped under "Unassigned"
  def racks_by_row
    equipment_racks.order(:row, :name).group_by { |r| r.row.presence || "Unassigned" }
  end
end
