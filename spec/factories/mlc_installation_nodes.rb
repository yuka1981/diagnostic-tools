FactoryBot.define do
  factory :mlc_installation_node do
    association :mlc_installation
    association :node
    status { :pending }
    step_current { 0 }
    step_total { 7 }

    trait :running do
      status { :running }
      started_at { Time.current }
      step_current { 3 }
      step_name { "Installing binary" }
    end

    trait :success do
      status { :success }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
      step_current { 7 }
      step_total { 7 }
    end

    trait :failed do
      status { :failed }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
      error_message { "Permission denied: /opt/qct/utils/qis/software" }
    end
  end
end
