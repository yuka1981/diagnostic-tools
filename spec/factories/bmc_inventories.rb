# frozen_string_literal: true

FactoryBot.define do
  factory :bmc_inventory do
    association :node
    processors { [] }
    memory { [] }
    storage { [] }
    network { [] }
    infiniband { [] }
    bios { {} }
    bmc_info { {} }
    collection_method { :redfish }
    captured_at { Time.current }

    trait :with_processors do
      processors do
        [
          {
            "model" => "Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz",
            "cores" => 20,
            "threads" => 40,
            "socket" => "CPU1",
            "manufacturer" => "Intel",
            "max_speed_mhz" => 3900
          },
          {
            "model" => "Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz",
            "cores" => 20,
            "threads" => 40,
            "socket" => "CPU2",
            "manufacturer" => "Intel",
            "max_speed_mhz" => 3900
          }
        ]
      end
    end

    trait :with_memory do
      memory do
        [
          {
            "size_gb" => 32,
            "type" => "DDR4",
            "speed_mhz" => 3200,
            "slot" => "DIMM_A1",
            "manufacturer" => "Samsung",
            "part_number" => "M393A4K40CB2-CVF"
          },
          {
            "size_gb" => 32,
            "type" => "DDR4",
            "speed_mhz" => 3200,
            "slot" => "DIMM_A2",
            "manufacturer" => "Samsung",
            "part_number" => "M393A4K40CB2-CVF"
          }
        ]
      end
    end

    trait :with_storage do
      storage do
        [
          {
            "name" => "Disk 0",
            "capacity_gb" => 480,
            "type" => "SSD",
            "manufacturer" => "Samsung",
            "model" => "MZ7LH480HAHQ",
            "serial_number" => "S45NNA0M800001"
          },
          {
            "name" => "Disk 1",
            "capacity_gb" => 1920,
            "type" => "NVMe",
            "manufacturer" => "Intel",
            "model" => "SSDPE2KX020T8",
            "serial_number" => "PHLJ1234567890"
          }
        ]
      end
    end

    trait :with_network do
      network do
        [
          {
            "id" => "NIC.Slot.1-1",
            "mac" => "00:11:22:33:44:55",
            "speed_gbps" => 25,
            "manufacturer" => "Mellanox",
            "model" => "ConnectX-6"
          },
          {
            "id" => "NIC.Slot.1-2",
            "mac" => "00:11:22:33:44:56",
            "speed_gbps" => 25,
            "manufacturer" => "Mellanox",
            "model" => "ConnectX-6"
          }
        ]
      end
    end

    trait :with_infiniband do
      infiniband do
        [
          {
            "guid" => "0x0011223344556677",
            "port_state" => "Active",
            "link_speed" => "HDR",
            "port_number" => 1
          }
        ]
      end
    end

    trait :with_bios do
      bios do
        {
          "vendor" => "AMI",
          "version" => "2.5.1",
          "release_date" => "2024-01-15"
        }
      end
    end

    trait :with_bmc_info do
      bmc_info do
        {
          "firmware_version" => "2.10.0",
          "ip_address" => "10.0.1.100",
          "mac_address" => "AA:BB:CC:DD:EE:FF",
          "manufacturer" => "Dell Inc.",
          "model" => "iDRAC9"
        }
      end
    end

    trait :via_redfish do
      collection_method { :redfish }
    end

    trait :via_ipmi do
      collection_method { :ipmi }
    end

    trait :complete do
      with_processors
      with_memory
      with_storage
      with_network
      with_infiniband
      with_bios
      with_bmc_info
    end
  end
end
