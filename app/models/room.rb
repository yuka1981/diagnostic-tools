# frozen_string_literal: true

class Room < ApplicationRecord
  # Associations
  # Note: We use EquipmentRack model (to avoid conflict with Rack gem) with foreign_key :room_id
  has_many :equipment_racks, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: true
end
