FactoryBot.define do
  factory :bmc_credential do
    association :node
    bmc_address { "10.0.1.100" }
    username { "admin" }
    password { "secret" }
  end
end
