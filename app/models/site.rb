# frozen_string_literal: true

class Site < ApplicationRecord
  has_many :racks, dependent: :destroy

  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
end
