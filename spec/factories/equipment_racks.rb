# frozen_string_literal: true

FactoryBot.define do
  factory :equipment_rack do
    sequence(:name) { |n| "R#{n.to_s.rjust(2, '0')}" }
    u_height { 42 }
    width { 19 }
    notes { nil }
    room { nil }

    trait :with_room do
      room
    end

    trait :small do
      u_height { 12 }
    end

    trait :medium do
      u_height { 24 }
    end

    trait :full_height do
      u_height { 48 }
    end
  end
end
