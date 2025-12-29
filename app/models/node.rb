# frozen_string_literal: true

class Node < ApplicationRecord
  # Enums
  enum :role, { compute: 0, login: 1, admin: 2 }, default: :compute
  enum :source, { manual: 0, csv: 1, agent_push: 2 }, default: :manual

  # Validations
  validates :hostname, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :role, presence: true
  validates :source, presence: true
  validates :ip, format: {
    with: /\A((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z|
          \A([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\z|
          \A([0-9a-fA-F]{1,4}:){1,7}:\z|
          \A([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}\z|
          \A([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}\z|
          \A([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}\z|
          \A([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}\z|
          \A([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}\z|
          \A[0-9a-fA-F]{1,4}:(:[0-9a-fA-F]{1,4}){1,6}\z|
          \A:((:[0-9a-fA-F]{1,4}){1,7}|:)\z|
          \A::([fF]{4}:)?((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/x,
    message: "is not a valid IP address"
  }, allow_blank: true

  # Constants
  ONLINE_THRESHOLD = 5.minutes

  # Instance methods
  def online?
    return false if last_seen_at.nil?

    last_seen_at > ONLINE_THRESHOLD.ago
  end

  def touch_last_seen
    update(last_seen_at: Time.current)
  end
end
