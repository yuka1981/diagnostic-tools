# frozen_string_literal: true

FactoryBot.define do
  factory :agent_event do
    association :node
    operation { :install }
    status { :pending }
    to_version { "v1.0.0" }

    trait :running do
      status { :running }
      started_at { Time.current }
    end

    trait :success do
      status { :success }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      error_message { "Operation failed" }
    end

    trait :rolled_back do
      status { :rolled_back }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      error_message { "Rolled back to previous version" }
    end

    trait :with_user do
      association :user
    end

    trait :with_release do
      association :agent_release
    end

    trait :install do
      operation { :install }
    end

    trait :upgrade do
      operation { :upgrade }
      from_version { "v0.9.0" }
    end

    trait :uninstall do
      operation { :uninstall }
      from_version { "v1.0.0" }
      to_version { nil }
    end
  end
end
