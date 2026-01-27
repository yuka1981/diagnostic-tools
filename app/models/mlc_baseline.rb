# frozen_string_literal: true

class MlcBaseline < ApplicationRecord
  belongs_to :node
  belongs_to :benchmark_run

  validates :metric_type, presence: true, uniqueness: { scope: :node_id }
  validates :value, presence: true

  scope :for_node, ->(node) { where(node: node) }
  scope :by_metric_type, ->(type) { where(metric_type: type) }
  scope :latest, -> { order(created_at: :desc) }
end
