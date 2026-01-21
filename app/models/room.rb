# frozen_string_literal: true

class Room < ApplicationRecord
  belongs_to :site
  has_many :server_racks, dependent: :restrict_with_error
  has_many :nodes, through: :server_racks

  validates :name, presence: true, uniqueness: { scope: :site_id }
  validates :floor_area_sqm, numericality: { greater_than: 0 }, allow_nil: true
  validates :power_capacity_kw, numericality: { greater_than: 0 }, allow_nil: true
  validates :cooling_capacity_kw, numericality: { greater_than: 0 }, allow_nil: true
  validates :max_rack_count, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  def rack_count
    server_racks.size
  end

  def total_u_capacity
    server_racks.sum(:u_height)
  end

  def total_u_used
    server_racks.joins(:nodes).sum("nodes.rack_height")
  end

  def utilization_percentage
    return 0.0 if total_u_capacity.zero?

    (total_u_used.to_f / total_u_capacity * 100).round(1)
  end

  def at_capacity?
    max_rack_count.present? && rack_count >= max_rack_count
  end
end
