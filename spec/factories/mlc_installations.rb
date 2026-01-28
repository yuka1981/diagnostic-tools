FactoryBot.define do
  factory :mlc_installation do
    uuid { SecureRandom.uuid }
    status { :pending }
    source_type { :upload }
    source_path { "/tmp/mlc_upload_#{SecureRandom.hex(8)}.tgz" }
    install_dir { "/opt/qct/utils/qis/software" }
    module_dir { "/opt/qct/utils/qis/modulefiles" }
    failure_mode { :stop_on_first }
    association :created_by, factory: :user

    trait :running do
      status { :running }
      started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      detected_version { "3.11" }
    end

    trait :with_checksum do
      checksum_algorithm { "sha256" }
      checksum_value { SecureRandom.hex(32) }
      checksum_verified { true }
    end
  end
end
