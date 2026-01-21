class ServerProduct < ApplicationRecord
  has_many :nodes, dependent: :nullify
  has_many_attached :images

  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }

  scope :by_series, ->(series) { where(product_series: series) if series.present? }
  scope :by_form_factor, ->(ff) { where(form_factor: ff) if ff.present? }
  scope :search_by_name, ->(q) { where("name ILIKE ?", "%#{q}%") if q.present? }

  def self.series_options
    Rails.cache.fetch("server_product_series_options", expires_in: 1.hour) do
      distinct.pluck(:product_series).compact.sort
    end
  end

  def self.form_factor_options
    Rails.cache.fetch("server_product_form_factor_options", expires_in: 1.hour) do
      distinct.pluck(:form_factor).compact.sort
    end
  end

  after_commit :invalidate_filter_caches

  before_validation :set_rack_height_from_form_factor

  def thumbnail_variant
    images.first&.variant(resize_to_fill: [ 48, 48 ])
  end

  def preprocess_image_variants!
    images.each do |image|
      image.variant(resize_to_fill: [ 48, 48 ]).processed
    end
  end

  private

  def invalidate_filter_caches
    Rails.cache.delete("server_product_series_options")
    Rails.cache.delete("server_product_form_factor_options")
  end

  def set_rack_height_from_form_factor
    return if rack_height.present? && rack_height > 0
    return unless form_factor.present?

    match = form_factor.match(/(\d+)U/i)
    self.rack_height = match[1].to_i if match
  end
end
