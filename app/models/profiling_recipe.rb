# frozen_string_literal: true

class ProfilingRecipe < ApplicationRecord
  # Associations
  has_many :profiling_runs, dependent: :restrict_with_error

  # Enums
  enum :status, { active: 0, archived: 1 }, default: :active

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :subcommand, presence: true, inclusion: { in: %w[report telemetry flame] }
  validates :module_name, presence: true
  validates :slug, uniqueness: true

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? }

  # Scopes
  scope :by_tool, ->(tool) { where(tool: tool) }

  # Instance methods
  def display_name
    "#{name} (#{tool})"
  end

  private

  def generate_slug
    self.slug = name.parameterize if name.present?
  end
end
