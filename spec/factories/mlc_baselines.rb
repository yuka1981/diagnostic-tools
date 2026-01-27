# frozen_string_literal: true

FactoryBot.define do
  factory :mlc_baseline do
    association :node
    association :benchmark_run
    metric_type { "idle_latency" }
    value { 78.2 }

    trait :peak_bandwidth do
      metric_type { "peak_bandwidth_all_reads" }
      value { 298450.0 }
    end

    trait :latency_matrix do
      metric_type { "latency_matrix_0_1" }
      value { 112.4 }
    end
  end
end
