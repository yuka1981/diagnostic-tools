# frozen_string_literal: true

FactoryBot.define do
  factory :node_state do
    association :node
    host_info { {} }
    cpu_info { {} }
    mem_info { {} }
    disk_info { [] }
    net_info { [] }
    network_inventory { {} }
    captured_at { Time.current }

    trait :with_host_info do
      host_info do
        {
          "hostname" => "node-001",
          "os" => "linux",
          "platform" => "ubuntu",
          "platform_version" => "22.04",
          "kernel" => "5.15.0-101-generic",
          "arch" => "x86_64"
        }
      end
    end

    trait :with_cpu_info do
      cpu_info do
        {
          "model" => "Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz",
          "cores" => 20,
          "threads" => 40,
          "flags" => %w[avx avx2 avx512f sse4_1 sse4_2]
        }
      end
    end

    trait :with_mem_info do
      mem_info do
        {
          "total" => 256.gigabytes,
          "free" => 200.gigabytes,
          "available" => 220.gigabytes
        }
      end
    end

    trait :with_disk_info do
      disk_info do
        [
          {
            "device" => "/dev/sda",
            "mountpoint" => "/",
            "fstype" => "ext4",
            "total" => 500.gigabytes,
            "used" => 100.gigabytes
          },
          {
            "device" => "/dev/sdb",
            "mountpoint" => "/data",
            "fstype" => "xfs",
            "total" => 2.terabytes,
            "used" => 500.gigabytes
          }
        ]
      end
    end

    trait :with_net_info do
      net_info do
        [
          {
            "interface" => "eth0",
            "ip" => "192.168.1.100",
            "mac" => "00:11:22:33:44:55",
            "speed" => 10000
          },
          {
            "interface" => "ib0",
            "ip" => "10.0.0.100",
            "mac" => "00:11:22:33:44:66",
            "speed" => 100000
          }
        ]
      end
    end

    trait :with_dmi_info do
      dmi_info do
        {
          "system" => {
            "manufacturer" => "Manufacturer Inc.",
            "product_name" => "SuperServer 123",
            "serial_number" => "SN123456789",
            "uuid" => "7d916442-2c24-11ee-be23-74d4dd2e9195",
            "sku_number" => "SKU-999",
            "family" => "Compute Node"
          },
          "bios" => {
            "vendor" => "AMI",
            "version" => "V1.2.3",
            "release_date" => "01/01/2025",
            "rom_size" => "64 MB"
          },
          "memory" => [
            {
              "locator" => "DIMM_A1",
              "bank_locator" => "P0_Node0_Channel0",
              "size" => "32 GB",
              "type" => "DDR4",
              "speed" => "3200 MT/s",
              "configured_speed" => "3200 MT/s",
              "manufacturer" => "Samsung",
              "part_number" => "M393A4K40CB2",
              "serial_number" => "123456"
            },
            {
              "locator" => "DIMM_A2",
              "bank_locator" => "P0_Node0_Channel0",
              "size" => "No Module Installed",
              "type" => "DDR4",
              "speed" => "Unknown",
              "configured_speed" => "Unknown"
            }
          ]
        }
      end
    end

    trait :complete do
      with_host_info
      with_cpu_info
      with_mem_info
      with_disk_info
      with_net_info
      with_dmi_info
    end
  end
end
