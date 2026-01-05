# frozen_string_literal: true

FactoryBot.define do
  factory :node_state do
    association :node
    host_info { {} }
    cpu_info { {} }
    mem_info { {} }
    disk_info { [] }
    net_info { [] }
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

    trait :complete do
      with_host_info
      with_cpu_info
      with_mem_info
      with_disk_info
      with_net_info
    end
  end
end
