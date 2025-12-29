# frozen_string_literal: true

class BenchmarkRun < ApplicationRecord
  # Associations
  belongs_to :node
  belongs_to :benchmark_recipe

  # Enums
  enum :status, {
    pending: 0,
    running: 1,
    success: 2,
    failed: 3,
    cancelled: 4
  }, default: :pending

  # Validations
  validates :status, presence: true

  # Scopes
  scope :recent, -> { order(Arel.sql("started_at DESC NULLS LAST")) }
  scope :completed, -> { where(status: [ :success, :failed ]) }
  scope :successful, -> { where(status: :success) }
  scope :for_node, ->(node) { where(node: node) }
  scope :in_last_24_hours, -> { where(started_at: 24.hours.ago..) }

  # Instance methods
  def duration
    return nil unless finished_at && started_at

    finished_at - started_at
  end

  def completed?
    success? || failed?
  end
end
