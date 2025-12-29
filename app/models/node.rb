# frozen_string_literal: true

require "ipaddr"

class Node < ApplicationRecord
  # Associations
  has_many :node_states, dependent: :destroy
  has_many :benchmark_runs, dependent: :destroy

  # Enums
  enum :role, { compute: 0, login: 1, admin: 2 }, default: :compute
  enum :source, { manual: 0, csv: 1, agent_push: 2 }, default: :manual

  # Validations
  validates :hostname, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :role, presence: true
  validates :source, presence: true

  # IP address validation using Ruby's IPAddr library
  validates_each :ip do |record, attr, value|
    next if value.blank?

    begin
      IPAddr.new(value)
    rescue IPAddr::InvalidAddressError
      record.errors.add(attr, "is not a valid IP address")
    end
  end

  # Constants
  ONLINE_THRESHOLD = 5.minutes

  # Scopes
  scope :online, -> { where(last_seen_at: ONLINE_THRESHOLD.ago..) }

  # Instance methods
  def online?
    return false if last_seen_at.nil?

    last_seen_at > ONLINE_THRESHOLD.ago
  end

  def touch_last_seen
    touch(:last_seen_at)
  end

  # Returns the most recent NodeState for this node
  def current_state
    node_states.latest_first.first
  end
end
