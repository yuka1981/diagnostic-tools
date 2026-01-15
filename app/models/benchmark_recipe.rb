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
  validate :validate_default_profile_is_json_object

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

  def validate_default_profile_is_json_object
    return if default_profile.blank?

    # When an invalid JSON string is assigned from a form to a jsonb attribute,
    # the attribute holds the original string instead of a parsed hash.
    return if default_profile.is_a?(Hash)

    errors.add(:default_profile, "must be a valid JSON object")
  end
end
