# frozen_string_literal: true

FactoryBot.define do
  factory :node do
    sequence(:hostname) { |n| "node-#{n.to_s.rjust(3, '0')}" }
    uuid { SecureRandom.uuid }
    ip { Faker::Internet.ip_v4_address }
    arch { %w[x86_64 aarch64].sample }
    role { :compute }
    source { :manual }
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

    trait :salt_discovery do
      source { :salt_discovery }
    end

    trait :salt_connected do
      salt_status { :connected }
    end

    trait :salt_disconnected do
      salt_status { :disconnected }
    end

    trait :salt_pending do
      salt_status { :pending }
    end

    trait :online do
      salt_status { :connected }
      last_seen_at { 1.minute.ago }
    end

    trait :offline do
      salt_status { :disconnected }
      last_seen_at { 10.minutes.ago }
    end

    trait :x86 do
      arch { "x86_64" }
    end

    trait :arm do
      arch { "aarch64" }
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
