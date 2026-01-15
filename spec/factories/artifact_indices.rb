# frozen_string_literal: true

FactoryBot.define do
  factory :artifact_index do
    benchmark_run
    sequence(:path) { |n| "/shared/artifacts/benchmark_#{n}/output.txt" }
    file_type { "txt" }
    size { 1024 }

    trait :log do
      sequence(:path) { |n| "/shared/artifacts/benchmark_#{n}/hpcg.log" }
      file_type { "log" }
      size { 2048 }
    end

    trait :json do
      sequence(:path) { |n| "/shared/artifacts/benchmark_#{n}/results.json" }
      file_type { "json" }
      size { 512 }
    end

    trait :yaml do
      sequence(:path) { |n| "/shared/artifacts/benchmark_#{n}/config.yaml" }
      file_type { "yaml" }
      size { 256 }
    end

    trait :large do
      size { 10.megabytes }
    end

    trait :with_stored_path do
      stored_path { |artifact| artifact.path.gsub("/shared/artifacts", Rails.root.join("storage", "artifacts").to_s) }
    end
  end
end
