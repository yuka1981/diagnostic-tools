# frozen_string_literal: true

class BenchmarkRecipe < ApplicationRecord
  # Associations
  has_many :benchmark_runs, dependent: :restrict_with_error

  # Enums
  enum :status, { active: 0, archived: 1 }, default: :active

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :version, presence: true, length: { maximum: 50 }
  validates :version, uniqueness: { scope: :name }
  validates :command, presence: true
  validates :slug, uniqueness: true

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? }

  # Scopes
  scope :by_name, ->(name) { where(name: name) }

  # Instance methods
  def display_name
    "#{name} v#{version}"
  end

  private

  def generate_slug
    base = "#{name}-#{version}"
    self.slug = base.parameterize
  end
end
