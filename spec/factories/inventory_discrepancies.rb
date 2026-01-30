FactoryBot.define do
  factory :inventory_discrepancy do
    node
    field_path { "memory.0.serial" }
    inband_value { "ABC123" }
    bmc_value { "XYZ789" }
    severity { :warning }

    trait :resolved do
      resolved_at { Time.current }
      resolution_note { "Verified correct" }
    end

    trait :critical do
      severity { :critical }
    end
  end
end
