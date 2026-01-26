# frozen_string_literal: true

FactoryBot.define do
  factory :inventory_discrepancy do
    node
    sequence(:field_path) { |n| "processors.#{n}.serial" }
    inband_value { "INBAND-12345" }
    bmc_value { "BMC-12345" }
    severity { :info }
    resolved_at { nil }
    resolution_note { nil }

    trait :warning do
      severity { :warning }
    end

    trait :critical do
      severity { :critical }
    end

    trait :resolved do
      resolved_at { 1.hour.ago }
      resolution_note { "Resolved by system administrator" }
    end
  end
end
