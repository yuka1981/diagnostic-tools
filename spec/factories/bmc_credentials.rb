FactoryBot.define do
  factory :bmc_credential do
    bmc_address { "192.168.1.100" }
    username { "admin" }
    password { "password" }
    protocol { :auto }
    verify_ssl { true }
    is_global_default { false }

    trait :global_default do
      node { nil }
      is_global_default { true }
    end

    trait :redfish do
      protocol { :redfish }
      port { 443 }
    end

    trait :ipmi do
      protocol { :ipmi }
      port { 623 }
    end
  end
end
