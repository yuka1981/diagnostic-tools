# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Roles: viewer (read-only), requester (can create runs), approver (can approve - V2)
  enum :role, { viewer: 0, requester: 1, approver: 2 }, default: :viewer

  # Valid fields for rack node preview customization
  VALID_RACK_NODE_PREVIEW_FIELDS = %w[cpu ram storage network load uptime last_seen os tags].freeze

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :role, presence: true
  validate :validate_rack_node_preview_fields

  private

  def validate_rack_node_preview_fields
    return if rack_node_preview_fields.blank?

    invalid_fields = rack_node_preview_fields - VALID_RACK_NODE_PREVIEW_FIELDS
    if invalid_fields.any?
      errors.add(:rack_node_preview_fields, "contains invalid fields: #{invalid_fields.join(', ')}")
    end
  end
end
