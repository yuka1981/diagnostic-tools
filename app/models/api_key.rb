class ApiKey < ApplicationRecord
  # Enums
  enum :status, { active: 0, revoked: 1 }, default: :active

  # Validations
  validates :name, presence: true
  validates :token, presence: true, uniqueness: true

  # Callbacks
  before_validation :generate_token, on: :create

  # Scopes
  scope :active, -> { where(status: :active) }

  def touch_last_used
    update_column(:last_used_at, Time.current)
  end

  private

  def generate_token
    self.token ||= SecureRandom.hex(24)
  end
end
