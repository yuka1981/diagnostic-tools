# frozen_string_literal: true

require "ipaddr"

class Node < ApplicationRecord
  # Associations
  has_many :node_states, dependent: :destroy
  has_many :benchmark_runs, dependent: :destroy
  belongs_to :api_key, optional: true

  # Enums
  enum :role, { compute: 0, login: 1, admin: 2 }, default: :compute
  enum :source, { manual: 0, csv: 1, agent_push: 2 }, default: :manual
  enum :ssh_connect_method, { global_bastion: 0, custom_bastion: 1, direct: 2 }, default: :global_bastion

  # Validations
  validates :hostname, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :uuid, uniqueness: true, allow_blank: true
  validates :role, presence: true
  validates :source, presence: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
  validates :ssh_user, length: { maximum: 255 }
  validates :arch, inclusion: { in: %w[x86_64 aarch64 arm64], allow_blank: true }
  validate :hostname_not_localhost
  validate :ip_not_localhost

  # Callbacks
  before_validation :generate_uuid, on: :create

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
  HEARTBEAT_ONLINE_THRESHOLD = 2.minutes
  DEFAULT_AGENT_PATH = "hpc-agent"

  # Scopes
  scope :online, -> { where(last_heartbeat_at: HEARTBEAT_ONLINE_THRESHOLD.ago..) }

  # Instance methods
  def online?
    return false if last_heartbeat_at.nil?

    last_heartbeat_at > HEARTBEAT_ONLINE_THRESHOLD.ago
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

  # Returns the API token for this node, checking both direct storage and ApiKey association
  # Priority: direct api_token column > associated ApiKey's token
  def effective_api_token
    api_token.presence || api_key&.token
  end

  def use_jump_host?
    jump_host.present?
  end

  def status
    online? ? :online : :offline
  end

  # Returns true if the node has any pending or running benchmark runs
  # Used to prevent agent updates while benchmarks are in progress
  def busy?
    benchmark_runs.where(status: %i[pending running]).exists?
  end

  # Class method to check if a hostname/IP is localhost
  # Can be used by controllers for early validation
  def self.localhost?(value)
    return false if value.blank?

    normalized = value.to_s.downcase.strip
    normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def hostname_not_localhost
    return if hostname.blank?

    if self.class.localhost?(hostname)
      errors.add(:hostname, "cannot be localhost. Please use a remote hostname or IP address.")
    end
  end

  def ip_not_localhost
    return if ip.blank?

    if self.class.localhost?(ip)
      errors.add(:ip, "cannot be a localhost address. Please use a remote IP address.")
    end
  end
end
