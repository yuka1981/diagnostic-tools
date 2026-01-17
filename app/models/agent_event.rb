# frozen_string_literal: true

class AgentEvent < ApplicationRecord
  belongs_to :node
  belongs_to :user, optional: true
  belongs_to :agent_release, optional: true

  enum :operation, { install: "install", upgrade: "upgrade", uninstall: "uninstall" }
  enum :status, { pending: "pending", running: "running", success: "success", failed: "failed", rolled_back: "rolled_back" }

  validates :operation, presence: true
  validates :status, presence: true

  def duration
    return nil unless started_at && completed_at

    completed_at - started_at
  end

  def mark_running!
    update!(status: :running, started_at: Time.current)
  end

  def mark_success!
    update!(status: :success, completed_at: Time.current)
  end

  def mark_failed!(message:, details: {})
    update!(
      status: :failed,
      error_message: message,
      error_details: details,
      completed_at: Time.current
    )
  end

  def mark_rolled_back!(message:)
    update!(
      status: :rolled_back,
      error_message: message,
      completed_at: Time.current
    )
  end
end
