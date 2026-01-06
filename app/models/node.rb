# frozen_string_literal: true

require "ipaddr"

class Node < ApplicationRecord
  # Virtual attributes for form
  attr_accessor :ssh_key, :password

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
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
  validates :ssh_user, length: { maximum: 255 }
  validates :arch, inclusion: { in: %w[x86_64 aarch64 arm64], allow_blank: true }

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
  DEFAULT_AGENT_PATH = "agent"

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

  def effective_agent_path
    agent_path.presence || DEFAULT_AGENT_PATH
  end

  def use_jump_host?
    jump_host.present?
  end
end
