FactoryBot.define do
  factory :inventory_discrepancy do
    association :node
    field_path { "cpu.model" }
  end
end
