# frozen_string_literal: true

class ProfilingRun < ApplicationRecord
  # Associations
  belongs_to :node
  belongs_to :profiling_recipe, optional: true
  belongs_to :user, optional: true
  has_many :profiling_artifacts, dependent: :destroy

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
  validates :subcommand, presence: true
  validates :uuid, presence: true, uniqueness: true

  # Callbacks
  before_validation :generate_uuid, on: :create
  after_create_commit :broadcast_new_run
  after_update_commit :broadcast_status_update

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: %i[success failed cancelled]) }
  scope :for_node, ->(node) { where(node: node) }

  # Instance methods
  def duration
    return nil unless finished_at && started_at

    finished_at - started_at
  end

  def completed?
    success? || failed? || cancelled?
  end

  # Creates a new run with the same configuration for re-running
  def build_rerun(user:)
    self.class.new(
      node: node,
      profiling_recipe: profiling_recipe,
      subcommand: subcommand,
      options: options,
      user: user
    )
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def broadcast_new_run
    broadcast_prepend_to(
      node,
      target: "profiling_runs_tbody",
      partial: "profiling_runs/run_row",
      locals: { run: self }
    )
  end

  def broadcast_status_update
    broadcast_replace_to(
      node,
      target: "profiling_run_#{id}",
      partial: "profiling_runs/run_row",
      locals: { run: self }
    )
  end
end
