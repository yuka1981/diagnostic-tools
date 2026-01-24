# frozen_string_literal: true

class ProfilingArtifact < ApplicationRecord
  belongs_to :profiling_run

  validates :filename, presence: true

  def downloadable?
    file_path.present? && File.exist?(file_path)
  end

  def content_type
    case file_type
    when "html" then "text/html"
    when "json" then "application/json"
    when "svg" then "image/svg+xml"
    when "txt" then "text/plain"
    else "application/octet-stream"
    end
  end
end
