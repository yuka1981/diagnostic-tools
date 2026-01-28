class MlcInstallationNode < ApplicationRecord
  belongs_to :mlc_installation
  belongs_to :node

  enum :status, { pending: 0, running: 1, success: 2, failed: 3, skipped: 4 }, default: :pending

  def completed?
    success? || failed? || skipped?
  end

  def duration
    return nil unless started_at && completed_at

    completed_at - started_at
  end
end
