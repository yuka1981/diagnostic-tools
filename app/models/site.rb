# frozen_string_literal: true

class Site < ApplicationRecord
  has_many :rooms, dependent: :destroy
  has_many :server_racks, through: :rooms

  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
end
