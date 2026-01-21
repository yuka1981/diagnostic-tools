# frozen_string_literal: true

FactoryBot.define do
  factory :room do
    site
    sequence(:name) { |n| "Room #{n}" }
    description { "A test room" }
  end
end
