# frozen_string_literal: true

FactoryBot.define do
  factory :notification do
    association :user
    notification_type { "agent_install" }
    status { "pending" }
    title { "Test notification" }
    message { nil }
    metadata { {} }
    read { false }
    archived { false }

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      message { "Something went wrong" }
    end

    trait :read do
      read { true }
    end

    trait :archived do
      archived { true }
    end

    trait :with_progress do
      running
      metadata { { "progress_percent" => 50 } }
    end

    trait :with_resource do
      association :resource, factory: :node
    end
  end
end
