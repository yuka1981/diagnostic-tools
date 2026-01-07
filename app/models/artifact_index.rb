# frozen_string_literal: true

class ArtifactIndex < ApplicationRecord
  belongs_to :benchmark_run

  validates :path, presence: true
  validates :file_type, presence: true
end
