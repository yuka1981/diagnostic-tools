# frozen_string_literal: true

require "ipaddr"

class Node < ApplicationRecord
  include RangeOverlap

  # Associations
  has_many :node_states, dependent: :destroy
  has_many :bmc_inventories, dependent: :destroy
  has_many :benchmark_runs, dependent: :destroy
  has_many :profiling_runs, dependent: :destroy
  has_many :inventory_discrepancies, dependent: :destroy
  has_one :bmc_credential, dependent: :destroy
  belongs_to :api_key, optional: true
  belongs_to :server_rack, foreign_key: :rack_id, optional: true
  belongs_to :server_product, optional: true

  # Enums - removed custom_bastion, only global_bastion and direct remain
  enum :role, { compute: 0, login: 1, admin: 2 }, default: :compute
  enum :source, { manual: 0, csv: 1, agent_push: 2 }, default: :manual
  enum :ssh_connect_method, { global_bastion: 0, direct: 2 }, default: :global_bastion

  # Validations
  validates :hostname, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :uuid, uniqueness: true, allow_blank: true
  validates :role, presence: true
  validates :source, presence: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
  validates :ssh_user, length: { maximum: 255 }
  validates :arch, inclusion: { in: %w[x86_64 aarch64 arm64], allow_blank: true }
  validates :rack_height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :hostname_not_localhost
  validate :ip_not_localhost
  validate :rack_position_required_when_racked
  validate :rack_position_within_bounds
  validate :no_overlapping_nodes

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
  scope :unracked, -> { where(rack_id: nil) }
  scope :racked, -> { where.not(rack_id: nil) }

  # Scope that adds BMC status counts for efficient node list display
  # Adds virtual attributes: has_bmc_inventory, unresolved_discrepancy_count, latest_bmc_health
  scope :with_bmc_status, lambda {
    # Subquery for latest BMC inventory per node
    latest_bmc_subquery = <<~SQL.squish
      LEFT JOIN LATERAL (
        SELECT bmc_inventories.id AS bmc_id, bmc_inventories.bmc_info
        FROM bmc_inventories
        WHERE bmc_inventories.node_id = nodes.id
        ORDER BY bmc_inventories.captured_at DESC
        LIMIT 1
      ) AS latest_bmc ON true
    SQL

    # Subquery for unresolved discrepancy counts
    discrepancy_count_subquery = <<~SQL.squish
      LEFT JOIN (
        SELECT node_id, COUNT(*) AS unresolved_count
        FROM inventory_discrepancies
        WHERE resolved_at IS NULL
        GROUP BY node_id
      ) AS discrepancy_counts ON discrepancy_counts.node_id = nodes.id
    SQL

    from("nodes #{latest_bmc_subquery} #{discrepancy_count_subquery}")
      .select(
        "nodes.*",
        "latest_bmc.bmc_id IS NOT NULL AS has_bmc_inventory",
        "latest_bmc.bmc_info->>'health' AS latest_bmc_health",
        "COALESCE(discrepancy_counts.unresolved_count, 0) AS unresolved_discrepancy_count"
      )
  }

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

  def status
    online? ? :online : :offline
  end

  # Simplified effective_* methods using override flags
  # If override flag is true, use node value. Otherwise, use global default.

  def effective_ssh_user
    ssh_user_override? ? ssh_user : SshSetting.current.ssh_user
  end

  def effective_ssh_port
    ssh_port_override? ? ssh_port : SshSetting.current.ssh_port
  end

  def effective_ssh_connect_method
    ssh_connect_method_override? ? ssh_connect_method : "global_bastion"
  end

  def effective_ssh_key
    ssh_key_override? ? ssh_key : SshSetting.current.ssh_key
  end

  def effective_ssh_password
    ssh_password_override? ? ssh_password : SshSetting.current.ssh_password
  end

  def effective_sudo_credential
    sudo_credential_override? ? sudo_credential : SshSetting.current.sudo_credential
  end

  # Returns true if the node has any pending or running benchmark runs
  # Used to prevent agent updates while benchmarks are in progress
  def busy?
    benchmark_runs.where(status: %i[pending running]).exists?
  end

  # Returns the BMC credential to use for connecting to this node's BMC
  # Falls back to global default if no node-specific credential exists
  def bmc_credential_for_connection
    bmc_credential || BmcCredential.global_default_record
  end

  # Returns the most recent BMC inventory for this node
  def latest_bmc_inventory
    bmc_inventories.order(captured_at: :desc).first
  end

  # Returns unresolved inventory discrepancies for this node
  def unresolved_discrepancies
    inventory_discrepancies.unresolved
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

  def rack_position_required_when_racked
    return unless rack_id.present? && rack_position.blank?

    errors.add(:rack_position, "can't be blank when rack is assigned")
  end

  def rack_position_within_bounds
    return unless server_rack.present? && rack_position.present?

    if rack_position < 1
      errors.add(:rack_position, "must be greater than or equal to 1")
    elsif rack_position > server_rack.u_height
      errors.add(:rack_position, "must be less than or equal to #{server_rack.u_height}")
    elsif (rack_position + (rack_height || 1) - 1) > server_rack.u_height
      errors.add(:base, "Node extends beyond rack height (position #{rack_position} + height #{rack_height} - 1 = #{rack_position + rack_height - 1}, rack height is #{server_rack.u_height})")
    end
  end

  def no_overlapping_nodes
    return unless server_rack.present? && rack_position.present?

    node_top = rack_position + (rack_height || 1) - 1
    overlapping = server_rack.nodes.where.not(id: id).find do |other|
      other_top = other.rack_position + (other.rack_height || 1) - 1
      ranges_overlap?(rack_position, node_top, other.rack_position, other_top)
    end

    if overlapping
      errors.add(:base, "Position overlaps with existing node #{overlapping.hostname}")
    end
  end
end
