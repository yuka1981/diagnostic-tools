FactoryBot.define do
  factory :bmc_inventory do
    association :node
    captured_at { Time.current }
  end
end
