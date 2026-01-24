# frozen_string_literal: true

class ArtifactIndex < ApplicationRecord
  belongs_to :benchmark_run

  validates :path, presence: true
  validates :file_type, presence: true

  # Returns the effective file path for display/download
  # Prefers stored_path (server-managed) over original path
  def effective_path
    stored_path.presence || path
  end

  # Checks if the artifact file is available for download
  # Returns true if either stored_path or original path exists
  def downloadable?
    (stored_path.present? && File.exist?(stored_path)) ||
      (path.present? && File.exist?(path))
  end

  # Returns the filename for display
  def filename
    File.basename(effective_path)
  end

  # Returns validated path for safe file download
  # Prefers stored_path (server-managed) over legacy path
  # @return [String, nil] Safe file path or nil if invalid/missing
  def safe_download_path
    validate_stored_path || validate_legacy_path
  end

  private

  def validate_stored_path
    return nil if stored_path.blank?

    storage_base = Rails.configuration.x.artifacts_storage_path.presence ||
                   Rails.root.join("storage", "artifacts").to_s

    clean_path = Pathname.new(stored_path).cleanpath.to_s

    return nil unless clean_path.start_with?(storage_base)
    return nil unless File.file?(clean_path)

    clean_path
  end

  def validate_legacy_path
    return nil if path.blank?

    base_path = Rails.configuration.x.artifacts_base_path
    base_path = "/shared/artifacts" unless base_path.is_a?(String) && base_path.present?

    allowed_base = Pathname.new(base_path).cleanpath.to_s
    clean_path = Pathname.new(path).cleanpath.to_s

    return nil unless clean_path.start_with?(allowed_base + File::SEPARATOR) || clean_path == allowed_base
    return nil unless File.file?(clean_path)

    clean_path
  end
end
