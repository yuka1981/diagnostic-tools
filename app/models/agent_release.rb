# frozen_string_literal: true

class AgentRelease < ApplicationRecord
  # ActiveStorage attachment for the agent binary
  has_one_attached :binary

  # Enums - status values from the feature request
  enum :status, { active: 0, deprecated: 1, recalled: 2 }, default: :active

  # Validations
  validates :version, presence: true, uniqueness: true, length: { maximum: 50 }
  validates :version, format: {
    with: /\Av?\d+\.\d+(\.\d+)?(-[\w.]+)?\z/,
    message: "must be a valid semantic version (e.g., v1.0.0, 1.2.3-beta)"
  }
  validates :release_notes, length: { maximum: 10_000 }
  validate :binary_attached, on: :create
  validate :binary_content_type

  # Callbacks
  before_save :calculate_checksum, if: :should_calculate_checksum?
  after_commit :ensure_checksum_calculated, on: %i[create update], if: :needs_checksum_recalculation?

  # Scopes
  scope :latest_first, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) }

  # Class methods
  def self.latest
    active.latest_first.first
  end

  # Instance methods
  def display_name
    "Agent #{version}"
  end

  def binary_filename
    binary.attached? ? binary.filename.to_s : nil
  end

  def binary_size
    binary.attached? ? binary.byte_size : 0
  end

  def formatted_size
    return "—" if binary_size.zero?

    units = %w[B KB MB GB]
    size = binary_size.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    format("%.2f %s", size, units[unit_index])
  end

  # Mark binary as updated when a new attachment is added
  def binary=(attachable)
    @binary_updated = true
    super
  end

  # Check if checksum is valid SHA256 hex format (64 hex characters)
  def valid_sha256_checksum?
    checksum.present? && checksum.match?(/\A[a-f0-9]{64}\z/i)
  end

  # Recalculate and save checksum from binary
  # Returns true if successful, false otherwise
  def recalculate_checksum!
    return false unless binary.attached?

    begin
      new_checksum = Digest::SHA256.hexdigest(binary.download)
      update_column(:checksum, new_checksum)
      true
    rescue ActiveStorage::FileNotFoundError => e
      Rails.logger.warn "[AgentRelease] Cannot recalculate checksum for #{version}: #{e.message}"
      false
    end
  end

  # Class method to recalculate all invalid checksums
  def self.recalculate_invalid_checksums!
    results = { success: 0, failed: 0, skipped: 0 }

    find_each do |release|
      if release.valid_sha256_checksum?
        results[:skipped] += 1
        next
      end

      if release.recalculate_checksum!
        results[:success] += 1
        Rails.logger.info "[AgentRelease] Recalculated checksum for #{release.version}"
      else
        results[:failed] += 1
        Rails.logger.error "[AgentRelease] Failed to recalculate checksum for #{release.version}"
      end
    end

    results
  end

  private

  def should_calculate_checksum?
    return false unless binary.attached?
    return true if new_record?
    return true if @binary_updated

    # Also recalculate if checksum is missing or invalid format
    checksum.blank? || !valid_sha256_checksum?
  end

  def needs_checksum_recalculation?
    binary.attached? && !valid_sha256_checksum?
  end

  def ensure_checksum_calculated
    # After commit, if checksum is still invalid, try to recalculate
    # This handles cases where the file wasn't available during before_save
    recalculate_checksum! if needs_checksum_recalculation?
  end

  def calculate_checksum
    return unless binary.attached?

    # Download the blob content and calculate SHA256 hex
    begin
      self.checksum = Digest::SHA256.hexdigest(binary.download)
    rescue ActiveStorage::FileNotFoundError
      # File not available yet - leave checksum blank
      # after_commit callback will try to recalculate
      Rails.logger.debug "[AgentRelease] Binary not available during save, checksum will be calculated after commit"
      self.checksum = nil
    end
  end

  def binary_attached
    return if binary.attached?

    errors.add(:binary, "must be attached")
  end

  def binary_content_type
    return unless binary.attached?

    # Accept common binary types for executables
    allowed_types = %w[
      application/octet-stream
      application/x-executable
      application/x-elf
      application/x-mach-binary
    ]

    return if allowed_types.include?(binary.content_type)

    # Also allow if filename suggests it's an executable (no extension or common patterns)
    filename = binary.filename.to_s
    return if filename.match?(/\A[\w.-]+\z/) && !filename.include?(".")

    errors.add(:binary, "must be an executable binary file")
  end
end
