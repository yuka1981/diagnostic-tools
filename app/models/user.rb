# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Roles: viewer (read-only), requester (can create runs), approver (can approve - V2)
  enum :role, { viewer: 0, requester: 1, approver: 2 }, default: :viewer

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :role, presence: true
end
