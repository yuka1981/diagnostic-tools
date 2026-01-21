# frozen_string_literal: true

class ServerRack < ApplicationRecord
  self.table_name = "racks"
  belongs_to :room
  has_many :nodes, foreign_key: :rack_id

  delegate :site, to: :room

  enum :status, { active: 0, planned: 1, decommissioned: 2 }, default: :active

  validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :room_id }
  validates :facility_id, uniqueness: { scope: :room_id }, allow_nil: true
  validates :u_height, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :width_mm, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :depth_mm, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :max_weight_kg, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def utilization
    nodes.sum(:rack_height)
  end

  def utilization_percentage
    return 0.0 if u_height.zero?

    (utilization.to_f / u_height * 100).round(1)
  end
end
