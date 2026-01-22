# frozen_string_literal: true

FactoryBot.define do
  factory :profiling_run do
    association :node
    association :profiling_recipe
    subcommand { "report" }
    status { :pending }
    options { {} }

    trait :running do
      status { :running }
      started_at { 5.minutes.ago }
    end

    trait :success do
      status { :success }
      started_at { 10.minutes.ago }
      finished_at { 5.minutes.ago }
      metrics do
        {
          "cpu_model" => "Intel Xeon Gold 6248",
          "cores" => 40,
          "turbo_enabled" => true
        }
      end
    end

    trait :failed do
      status { :failed }
      started_at { 10.minutes.ago }
      finished_at { 9.minutes.ago }
      error_message { "Module perfspect/3.13.0 not found" }
    end

    trait :cancelled do
      status { :cancelled }
      started_at { 10.minutes.ago }
      finished_at { 8.minutes.ago }
    end

    trait :telemetry do
      subcommand { "telemetry" }
      options { { "duration" => 60 } }
    end

    trait :flame do
      subcommand { "flame" }
      options { { "duration" => 30 } }
    end

    trait :custom do
      profiling_recipe { nil }
    end
  end
end
