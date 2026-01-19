# frozen_string_literal: true

class AgentBinary < ApplicationRecord
  SUPPORTED_ARCHITECTURES = %w[x86_64 aarch64].freeze

  belongs_to :agent_release

  # ActiveStorage attachment for the architecture-specific binary
  has_one_attached :binary

  # Validations
  validates :arch, presence: true, inclusion: { in: SUPPORTED_ARCHITECTURES }
  validates :arch, uniqueness: { scope: :agent_release_id, message: "already has a binary for this release" }
  validate :binary_attached
  validate :binary_content_type

  # Callbacks
  before_save :calculate_checksum, if: :should_calculate_checksum?
  after_commit :ensure_checksum_calculated, on: %i[create update], if: :needs_checksum_recalculation?

  # Scopes
  scope :for_arch, ->(arch) { where(arch: arch) }

  # Instance methods
  def display_name
    "#{agent_release.version} (#{arch})"
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
  def recalculate_checksum!
    return false unless binary.attached?

    begin
      new_checksum = Digest::SHA256.hexdigest(binary.download)
      update_column(:checksum, new_checksum)
      true
    rescue ActiveStorage::FileNotFoundError => e
      Rails.logger.warn "[AgentBinary] Cannot recalculate checksum for #{display_name}: #{e.message}"
      false
    end
  end

  private

  def should_calculate_checksum?
    return false unless binary.attached?
    return true if new_record?
    return true if @binary_updated

    checksum.blank? || !valid_sha256_checksum?
  end

  def needs_checksum_recalculation?
    binary.attached? && !valid_sha256_checksum?
  end

  def ensure_checksum_calculated
    recalculate_checksum! if needs_checksum_recalculation?
  end

  def calculate_checksum
    return unless binary.attached?

    begin
      self.checksum = Digest::SHA256.hexdigest(binary.download)
    rescue ActiveStorage::FileNotFoundError
      Rails.logger.debug "[AgentBinary] Binary not available during save, checksum will be calculated after commit"
      self.checksum = nil
    end
  end

  def binary_attached
    return if binary.attached?

    errors.add(:binary, "must be attached")
  end

  def binary_content_type
    return unless binary.attached?

    allowed_types = %w[
      application/octet-stream
      application/x-executable
      application/x-elf
      application/x-mach-binary
    ]

    return if allowed_types.include?(binary.content_type)

    filename = binary.filename.to_s
    return if filename.match?(/\A[\w.-]+\z/) && !filename.include?(".")

    errors.add(:binary, "must be an executable binary file")
  end
end
