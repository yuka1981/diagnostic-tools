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

  private

  def should_calculate_checksum?
    return false unless binary.attached?
    return true if new_record?
    return true if @binary_updated

    # Also recalculate if checksum is missing
    checksum.blank?
  end

  def calculate_checksum
    return unless binary.attached?

    # Download the blob content and calculate SHA256
    # Handle case where blob file might not exist yet (e.g., during tests)
    begin
      self.checksum = Digest::SHA256.hexdigest(binary.download)
    rescue ActiveStorage::FileNotFoundError
      # In test environment or when file is pending, use blob checksum if available
      self.checksum = binary.blob&.checksum
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
