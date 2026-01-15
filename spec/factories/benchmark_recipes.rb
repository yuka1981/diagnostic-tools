# frozen_string_literal: true

FactoryBot.define do
  factory :benchmark_recipe do
    sequence(:name) { |n| "benchmark-#{n}" }
    sequence(:version) { |n| "1.#{n}.0" }
    sequence(:slug) { |n| "benchmark-#{n}-slug" }
    command { "benchmark" }
    default_profile { {} }
    timeout_seconds { 3600 }
    status { :active }

    trait :hpcg do
      name { "hpcg" }
      version { "3.1" }
      slug { "hpcg-3-1" }
      command { "hpcg" }
      description { "High Performance Conjugate Gradients benchmark" }
      default_profile do
        {
          "nx" => 104,
          "ny" => 104,
          "nz" => 104,
          "runtime" => 1800,
          "modules" => %w[gcc/12.2.0 openmpi/4.1.4]
        }
      end
    end

    trait :hpl do
      name { "hpl" }
      version { "2.3" }
      slug { "hpl-2-3" }
      command { "hpl" }
      description { "High Performance Linpack benchmark" }
      default_profile do
        {
          "problem_size" => 10000,
          "block_size" => 192,
          "modules" => %w[gcc/12.2.0 openmpi/4.1.4 openblas/0.3.21]
        }
      end
    end

    trait :archived do
      status { :archived }
    end
  end
end
