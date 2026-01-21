class ServerProduct < ApplicationRecord
  has_many :nodes, dependent: :nullify
  has_many_attached :images

  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }

  scope :by_series, ->(series) { where(product_series: series) if series.present? }
  scope :by_form_factor, ->(ff) { where(form_factor: ff) if ff.present? }
  scope :search_by_name, ->(q) { where("name ILIKE ?", "%#{q}%") if q.present? }

  before_validation :set_rack_height_from_form_factor

  private

  def set_rack_height_from_form_factor
    return if rack_height.present? && rack_height > 0
    return unless form_factor.present?

    match = form_factor.match(/(\d+)U/i)
    self.rack_height = match[1].to_i if match
  end
end
