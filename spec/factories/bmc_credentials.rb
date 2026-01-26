# frozen_string_literal: true

FactoryBot.define do
  factory :bmc_credential do
    sequence(:bmc_address) { |n| "192.168.100.#{n}" }
    username { "admin" }
    password { "password123" }
    protocol { :auto }
    port { nil }
    verify_ssl { true }
    is_global_default { false }
    node { nil }

    trait :global_default do
      is_global_default { true }
      node { nil }
    end

    trait :redfish do
      protocol { :redfish }
      port { 443 }
    end

    trait :ipmi do
      protocol { :ipmi }
      port { 623 }
    end

    trait :with_node do
      node
    end
  end
end
