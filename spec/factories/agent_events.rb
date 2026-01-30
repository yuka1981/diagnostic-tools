FactoryBot.define do
  factory :agent_event do
    association :node
    operation { "install" }
    status { "pending" }
  end
end
