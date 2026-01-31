# frozen_string_literal: true

class BmcSensorReading < ApplicationRecord
  belongs_to :node

  validates :sensor_type, presence: true, inclusion: { in: %w[temperature fan power health] }
  validates :sensor_name, presence: true
  validates :value, presence: true
  validates :unit, presence: true
  validates :recorded_at, presence: true

  scope :for_node, ->(node_id) { where(node_id: node_id) }
  scope :of_type, ->(type) { where(sensor_type: type) }
  scope :since, ->(time) { where("recorded_at >= ?", time) }
  scope :latest, -> { order(recorded_at: :desc) }
end
