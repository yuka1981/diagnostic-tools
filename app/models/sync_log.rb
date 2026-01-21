class SyncLog < ApplicationRecord
  validates :source, presence: true

  scope :for_source, ->(source) { where(source: source) }
  scope :latest, -> { order(completed_at: :desc) }
end
