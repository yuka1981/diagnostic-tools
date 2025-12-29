# frozen_string_literal: true

FactoryBot.define do
  factory :benchmark_run do
    association :node
    association :benchmark_recipe
    status { :pending }
    started_at { nil }
    finished_at { nil }
    metrics { {} }
    error_message { nil }

    trait :running do
      status { :running }
      started_at { 10.minutes.ago }
      finished_at { nil }
    end

    trait :success do
      status { :success }
      started_at { 1.hour.ago }
      finished_at { 30.minutes.ago }
      metrics do
        {
          "gflops" => 45.67,
          "time" => 1823.45,
          "residual" => 1.23e-15,
          "iterations" => 50,
          "convergence" => true
        }
      end
    end

    trait :failed do
      status { :failed }
      started_at { 1.hour.ago }
      finished_at { 55.minutes.ago }
      error_message { "Build failed: missing module gcc/12.2.0" }
      metrics { {} }
    end

    trait :cancelled do
      status { :cancelled }
      started_at { 1.hour.ago }
      finished_at { 50.minutes.ago }
      error_message { "Cancelled by user" }
    end

    trait :with_hpcg_metrics do
      metrics do
        {
          "gflops" => rand(30.0..60.0).round(2),
          "time" => rand(1500.0..2000.0).round(2),
          "residual" => rand(1e-16..1e-14),
          "nx" => 104,
          "ny" => 104,
          "nz" => 104
        }
      end
    end
  end
end
