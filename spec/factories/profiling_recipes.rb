# frozen_string_literal: true

FactoryBot.define do
  factory :profiling_recipe do
    sequence(:name) { |n| "profiling-recipe-#{n}" }
    sequence(:slug) { |n| "profiling-recipe-#{n}" }
    tool { "perfspect" }
    subcommand { "report" }
    module_name { "perfspect/3.13.0" }
    default_options { {} }
    timeout_seconds { 300 }
    status { :active }

    trait :report do
      name { "Quick System Report" }
      slug { "quick-system-report" }
      subcommand { "report" }
      description { "Collect system configuration snapshot" }
    end

    trait :telemetry do
      name { "Performance Telemetry" }
      slug { "performance-telemetry" }
      subcommand { "telemetry" }
      description { "Collect live performance metrics" }
      default_options { { "duration" => 60 } }
    end

    trait :flame do
      name { "CPU Flame Graph" }
      slug { "cpu-flame-graph" }
      subcommand { "flame" }
      description { "Generate CPU flame graph" }
      default_options { { "duration" => 30 } }
    end

    trait :archived do
      status { :archived }
    end
  end
end
