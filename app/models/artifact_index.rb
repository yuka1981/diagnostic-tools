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
end
