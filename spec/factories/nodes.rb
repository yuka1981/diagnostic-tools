# frozen_string_literal: true

FactoryBot.define do
  factory :node do
    sequence(:hostname) { |n| "node-#{n.to_s.rjust(3, '0')}" }
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
  end
end
