# frozen_string_literal: true

class BenchmarkRun < ApplicationRecord
  # Associations
  belongs_to :node
  belongs_to :benchmark_recipe

  # Enums
  enum :status, {
    pending: 0,
    preparing: 1,
    building: 2,
    running: 3,
    uploading: 4,
    success: 5,
    failed: 6,
    lost: 7
  }, default: :pending

  # Validations
  validates :status, presence: true
  validates :uuid, presence: true, uniqueness: true

  # Callbacks
  before_validation :generate_uuid, on: :create
  after_create_commit :broadcast_new_run
  after_update_commit :broadcast_status_update

  # Scopes
  # Note: Sorting by created_at to align with latest task creation
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: %i[success failed lost]) }
  scope :successful, -> { where(status: :success) }
  scope :active, -> { where(status: %i[preparing building running]) }
  scope :for_node, ->(node) { where(node: node) }
  scope :in_last_24_hours, -> { where(started_at: 24.hours.ago..) }

  # Instance methods
  def duration
    return nil unless finished_at && started_at

    finished_at - started_at
  end

  def completed?
    success? || failed? || lost?
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def broadcast_new_run
    broadcast_prepend_to(
      "benchmark_runs",
      target: "benchmark_runs_tbody",
      partial: "benchmark_runs/run_row",
      locals: { run: self }
    )

    broadcast_replace_to(
      node,
      target: "latest_benchmark_node_#{node.id}",
      partial: "nodes/latest_benchmark",
      locals: { node: node }
    )
  end

  def broadcast_status_update
    broadcast_replace_to(
      "benchmark_runs",
      target: "benchmark_run_#{id}",
      partial: "benchmark_runs/run_row",
      locals: { run: self }
    )

    broadcast_replace_to(
      node,
      target: "latest_benchmark_node_#{node.id}",
      partial: "nodes/latest_benchmark",
      locals: { node: node }
    )
  end
end
