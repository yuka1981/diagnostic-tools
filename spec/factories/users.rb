# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }
    role { :viewer }

    trait :requester do
      role { :requester }
    end

    trait :approver do
      role { :approver }
    end
  end
end
