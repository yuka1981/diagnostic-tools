FactoryBot.define do
  factory :bmc_inventory do
    node
    processors { [] }
    memory { [] }
    storage { [] }
    network { [] }
    infiniband { [] }
    bios { {} }
    bmc_info { {} }
    collection_method { :redfish }
    captured_at { Time.current }
  end
end
