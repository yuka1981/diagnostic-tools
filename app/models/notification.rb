# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :resource, polymorphic: true, optional: true

  TYPES = %w[agent_install agent_update agent_uninstall benchmark inventory_collect product_sync profiling].freeze

  enum :status, { pending: "pending", running: "running", completed: "completed", failed: "failed" }

  validates :notification_type, presence: true, inclusion: { in: TYPES }
  validates :title, presence: true
  validates :status, presence: true

  scope :unread, -> { where(read: false, archived: false) }
  scope :active, -> { where(archived: false) }
  scope :for_dropdown, -> { active.order(created_at: :desc).limit(10) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(notification_type: type) if type.present? }
  scope :by_status, ->(status) { where(status: status) if status.present? }

  def progress_percent
    metadata["progress_percent"]
  end

  def in_progress?
    pending? || running?
  end

  def terminal?
    completed? || failed?
  end
end
