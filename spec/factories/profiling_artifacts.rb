# frozen_string_literal: true

FactoryBot.define do
  factory :profiling_artifact do
    association :profiling_run
    sequence(:filename) { |n| "report_#{n}.html" }
    file_type { "html" }
    file_path { "/shared/profiling/#{SecureRandom.uuid}/report.html" }
    file_size { 12345 }

    trait :html_report do
      filename { "system_report.html" }
      file_type { "html" }
    end

    trait :json_data do
      filename { "metrics.json" }
      file_type { "json" }
    end

    trait :flame_graph do
      filename { "flamegraph.svg" }
      file_type { "svg" }
    end
  end
end
