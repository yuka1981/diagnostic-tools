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
      ssh_connect_method_override { true }
    end

    trait :global_bastion do
      ssh_connect_method { :global_bastion }
    end

    # Override traits for node-specific SSH settings
    trait :with_ssh_user_override do
      ssh_user_override { true }
      ssh_user { "custom_user" }
    end

    trait :with_ssh_port_override do
      ssh_port_override { true }
      ssh_port { 2222 }
    end

    trait :racked do
      server_rack
      rack_position { 1 }
      rack_height { 1 }
    end

    trait :two_u do
      rack_height { 2 }
    end

    trait :four_u do
      rack_height { 4 }
    end
  end
end
