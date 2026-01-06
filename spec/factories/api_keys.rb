FactoryBot.define do
  factory :api_key do
    sequence(:name) { |n| "API Key #{n}" }
    status { :active }
  end
end
