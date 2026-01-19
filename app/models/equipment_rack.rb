# frozen_string_literal: true

# EquipmentRack represents a physical server rack in a data center.
# Note: Named EquipmentRack to avoid conflict with the Rack gem (web server interface).
# The table is still named 'racks' for cleaner database schema.
class EquipmentRack < ApplicationRecord
  self.table_name = "racks"

  # Associations
  belongs_to :room, optional: true
  has_many :nodes, foreign_key: :rack_id, dependent: :nullify

  # Validations
  validates :name, presence: true
  validates :name, uniqueness: { scope: :room_id }
  validates :u_height, numericality: { only_integer: true, greater_than: 0 }
  validates :width, numericality: { only_integer: true, greater_than: 0 }

  validate :u_height_not_below_occupied

  # Returns an array of unit data for rack elevation visualization
  # Each unit contains: { u: position, node: node_or_nil }
  # Returns units in descending order (top to bottom)
  def elevation_data(face: :front)
    face_value = Node.rack_faces[face]
    positioned_nodes = nodes.where.not(rack_position: nil).where(rack_face: face_value)

    # Build a mapping of unit position to node
    unit_to_node = {}
    positioned_nodes.each do |node|
      node.rack_position.upto(node.rack_position + node.rack_height - 1) do |unit|
        unit_to_node[unit] = node
      end
    end

    # Generate array from top to bottom
    u_height.downto(1).map do |unit|
      { u: unit, node: unit_to_node[unit] }
    end
  end

  # Returns the percentage of rack space occupied by nodes
  def utilization_percentage
    return 0 if u_height.nil? || u_height.zero?

    total_occupied = nodes.where.not(rack_position: nil).sum(:rack_height)
    (total_occupied.to_f / u_height * 100).round(1)
  end

  private

  def u_height_not_below_occupied
    return unless u_height_changed? && nodes.any?

    max_occupied = nodes.where.not(rack_position: nil)
                        .maximum(Arel.sql("rack_position + rack_height - 1"))
    if max_occupied && u_height < max_occupied
      errors.add(:u_height, "cannot be reduced below occupied position #{max_occupied}")
    end
  end
end
