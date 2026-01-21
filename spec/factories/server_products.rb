FactoryBot.define do
  factory :server_product do
    sequence(:name) { |n| "QuantaGrid D54Q-#{n}U" }
    product_series { "QuantaGrid" }
    form_factor { "2U" }
    rack_height { 2 }
    qct_product_url { "https://www.qct.io/product/index/Server/rackmount-server/QuantaGrid-D54Q-2U" }
    cpu_generations { [ "5th Gen Xeon" ] }
    socket_count { 2 }
    max_tdp_watts { 350 }
    max_memory_gb { 8192 }
    dimm_slots { 32 }
    memory_types { [ "DDR5" ] }
    max_memory_speed_mhz { 5600 }
    drive_bays { [ { "count" => 24, "type" => "NVMe", "form_factor" => "2.5" } ] }
    pcie_slots { [ { "count" => 4, "generation" => "5.0", "lanes" => 16 } ] }
    gpu_support { true }

    trait :one_u do
      form_factor { "1U" }
      rack_height { 1 }
    end

    trait :four_u do
      form_factor { "4U" }
      rack_height { 4 }
    end

    trait :quantaplex do
      product_series { "QuantaPlex" }
      sequence(:name) { |n| "QuantaPlex T42S-#{n}U" }
    end
  end
end
