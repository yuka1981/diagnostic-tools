# frozen_string_literal: true

FactoryBot.define do
  factory :server_rack do
    site
    sequence(:name) { |n| "Rack #{n}" }
    u_height { 42 }
    status { :active }

    trait :planned do
      status { :planned }
    end

    trait :decommissioned do
      status { :decommissioned }
    end

    trait :with_facility_id do
      sequence(:facility_id) { |n| "FAC-#{n.to_s.rjust(4, '0')}" }
    end
  end
end
