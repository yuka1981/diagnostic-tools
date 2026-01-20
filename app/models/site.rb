# frozen_string_literal: true

class Site < ApplicationRecord
  has_many :server_racks, dependent: :destroy

  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
end
