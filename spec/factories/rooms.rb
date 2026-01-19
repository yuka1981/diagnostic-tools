# frozen_string_literal: true

FactoryBot.define do
  factory :room do
    sequence(:name) { |n| "Room-#{n}" }
    description { "Test machine room" }
  end
end
