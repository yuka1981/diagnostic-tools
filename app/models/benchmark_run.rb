# frozen_string_literal: true

class BenchmarkRun < ApplicationRecord
  # Associations
  belongs_to :node
  belongs_to :benchmark_recipe
  has_many :artifact_indices, dependent: :destroy
  has_many :mlc_baselines, dependent: :destroy

  # Enums
  enum :status, {
    pending: 0,
    running: 1,
    success: 2,
    failed: 3,
    cancelled: 4
  }, default: :pending

  # Maps agent-reported status strings to model status symbols
  AGENT_STATUS_MAP = {
    "PASS" => :success,
    "FAIL" => :failed,
    "ERROR" => :failed,
    "RUNNING" => :running
  }.freeze

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
  scope :completed, -> { where(status: %i[success failed cancelled]) }
  scope :successful, -> { where(status: :success) }
  scope :for_node, ->(node) { where(node: node) }
  scope :in_last_24_hours, -> { where(started_at: 24.hours.ago..) }
  scope :recent_for_dashboard, ->(node = nil) {
    scope = recent.includes(:node, :benchmark_recipe)
                  .where.not(benchmark_recipe_id: nil)
                  .where.not(node_id: nil)
    scope = scope.for_node(node) if node
    scope.limit(10)
  }

  # Class methods
  # Converts agent status string to model status symbol
  # @param agent_status [String] Status from agent (PASS, FAIL, ERROR, RUNNING)
  # @return [Symbol, nil] Model status symbol or nil if unknown
  def self.status_from_agent(agent_status)
    AGENT_STATUS_MAP[agent_status]
  end

  # Instance methods
  def duration
    return nil unless finished_at && started_at

    finished_at - started_at
  end

  def completed?
    success? || failed? || cancelled?
  end

  # Creates a new run with the same configuration for re-running
  def build_rerun
    self.class.new(
      node: node,
      benchmark_recipe: benchmark_recipe,
      arguments: arguments,
      log_path: log_path
    )
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def broadcast_new_run
    # Broadcast to global benchmark runs list
    broadcast_prepend_to(
      "benchmark_runs",
      target: "benchmark_runs_tbody",
      partial: "benchmark_runs/run_row",
      locals: { run: self }
    )

    # Broadcast to node page - prepend to recent runs table
    broadcast_prepend_to(
      node,
      target: "node_recent_runs_tbody",
      partial: "nodes/benchmark_run_row",
      locals: { run: self }
    )
  end

  def broadcast_status_update
    # Broadcast to global benchmark runs list
    broadcast_replace_to(
      "benchmark_runs",
      target: "benchmark_run_#{id}",
      partial: "benchmark_runs/run_row",
      locals: { run: self }
    )

    # Broadcast to node page - update the run row
    broadcast_replace_to(
      node,
      target: "benchmark_run_#{id}",
      partial: "nodes/benchmark_run_row",
      locals: { run: self }
    )
  end
end
