# frozen_string_literal: true

FactoryBot.define do
  factory :node do
    sequence(:hostname) { |n| "node-#{n.to_s.rjust(3, '0')}" }
    uuid { SecureRandom.uuid }
    ip { Faker::Internet.ip_v4_address }
    arch { %w[x86_64 aarch64].sample }
    role { :compute }
    source { :manual }
    ssh_port { 22 }
    last_seen_at { nil }

    trait :login do
      role { :login }
    end

    trait :admin do
      role { :admin }
    end

    trait :csv do
      source { :csv }
    end

    trait :agent_push do
      source { :agent_push }
    end

    trait :online do
      last_seen_at { 1.minute.ago }
    end

    trait :offline do
      last_seen_at { 10.minutes.ago }
    end

    trait :x86 do
      arch { "x86_64" }
    end

    trait :arm do
      arch { "aarch64" }
    end

    trait :direct do
      ssh_connect_method { :direct }
    end

    trait :global_bastion do
      ssh_connect_method { :global_bastion }
    end

    trait :custom_bastion do
      ssh_connect_method { :custom_bastion }
      jump_host { "bastion.example.com" }
      jump_user { "bastion_user" }
      jump_port { 22 }
    end

    # Rack-related traits
    trait :in_rack do
      rack { association :equipment_rack }
      rack_position { 1 }
      rack_height { 1 }
      rack_face { :front }
    end

    trait :rear_mounted do
      rack_face { :rear }
    end

    trait :multi_u do
      rack_height { 2 }
    end
  end
end
