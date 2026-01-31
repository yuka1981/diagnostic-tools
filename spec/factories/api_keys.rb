FactoryBot.define do
  factory :api_key do
    sequence(:name) { |n| "API Key #{n}" }
    status { :active }

    trait :bmc_access do
      bmc_access { true }
    end
  end
end
