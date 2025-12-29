# frozen_string_literal: true

class BenchmarkRecipe < ApplicationRecord
  # Associations
  has_many :benchmark_runs, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :version, presence: true, length: { maximum: 50 }
  validates :version, uniqueness: { scope: :name }

  # Scopes
  scope :by_name, ->(name) { where(name: name) }

  # Instance methods
  def display_name
    "#{name} v#{version}"
  end
end
