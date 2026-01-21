FactoryBot.define do
  factory :sync_log do
    source { "qct" }
    products_added { 5 }
    products_updated { 10 }
    sync_errors { [] }
    completed_at { Time.current }

    trait :with_sync_errors do
      sync_errors { [ { "url" => "https://example.com", "error" => "Connection timeout" } ] }
    end

    trait :in_progress do
      completed_at { nil }
    end
  end
end
