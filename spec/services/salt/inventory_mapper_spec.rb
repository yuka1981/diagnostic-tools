require "rails_helper"

RSpec.describe Salt::InventoryMapper do
  describe "#call" do
    let(:grains) do
      {
        "host" => "node-01",
        "fqdn" => "node-01.cluster.local",
        "ip4_interfaces" => { "eth0" => [ "10.0.1.1" ], "lo" => [ "127.0.0.1" ] },
        "cpuarch" => "x86_64",
        "kernel" => "Linux",
        "kernelrelease" => "5.15.0-generic",
        "os" => "CentOS",
        "osrelease" => "8.5",
        "cpu_model" => "Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz",
        "num_cpus" => 40,
        "mem_total" => 256000,
        "disks" => [ "sda", "sdb" ],
        "SSDs" => [ "sda" ],
        "gpus" => []
      }
    end

    let(:dmi_data) do
      {
        "bios" => { "vendor" => "AMI", "version" => "1.2", "release_date" => "01/15/2024" },
        "system" => { "manufacturer" => "QCT", "product_name" => "QuantaPlex T42S-2U" },
        "baseboard" => { "manufacturer" => "QCT", "product_name" => "S6Q" }
      }
    end

    let(:numa_data) do
      {
        "node_count" => 2,
        "nodes" => {
          "0" => { "cpus" => [ 0, 1, 2, 3 ], "memory_mb" => 128000 },
          "1" => { "cpus" => [ 4, 5, 6, 7 ], "memory_mb" => 128000 }
        }
      }
    end

    let(:network_v2_data) do
      {
        "devices" => [
          { "name" => "eth0", "driver" => "i40e", "speed" => "25Gbit/s", "mac" => "aa:bb:cc:dd:ee:ff" }
        ]
      }
    end

    let(:mapper) do
      described_class.new(
        grains: grains,
        dmi: dmi_data,
        numa: numa_data,
        network_v2: network_v2_data
      )
    end

    it "maps grains to host_info with view-compatible field names" do
      result = mapper.call
      expect(result[:host][:hostname]).to eq("node-01")
      expect(result[:host][:ip]).to eq("10.0.1.1")
      expect(result[:host][:arch]).to eq("x86_64")
      expect(result[:host][:kernel]).to eq("Linux 5.15.0-generic")
      expect(result[:host][:os]).to eq("CentOS")
      expect(result[:host][:platform]).to eq("CentOS")
      expect(result[:host][:platform_version]).to eq("8.5")
    end

    it "maps grains to cpu_info with view-compatible field names" do
      result = mapper.call
      expect(result[:cpu][:model_name]).to eq("Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz")
      expect(result[:cpu][:cpus]).to eq(40)
    end

    it "maps numa data to cpu_info numa_info as formatted ranges" do
      result = mapper.call
      expect(result[:cpu][:numa_info]).to eq({
        "0" => "0-3",
        "1" => "4-7"
      })
    end

    it "formats non-contiguous CPU ranges correctly" do
      numa_data_gaps = {
        "node_count" => 1,
        "nodes" => {
          "0" => { "cpus" => [ 0, 1, 2, 5, 6, 10 ], "memory_mb" => 64000 }
        }
      }
      mapper = described_class.new(grains: grains, numa: numa_data_gaps)
      result = mapper.call
      expect(result[:cpu][:numa_info]["0"]).to eq("0-2,5-6,10")
    end

    it "maps memory total in bytes for format_bytes helper" do
      result = mapper.call
      expect(result[:memory][:total]).to eq(256000 * 1024 * 1024)
    end

    it "maps disks with device field name" do
      result = mapper.call
      expect(result[:disks].first[:device]).to eq("sda")
      expect(result[:disks].first[:type]).to eq("SSD")
      expect(result[:disks].last[:device]).to eq("sdb")
      expect(result[:disks].last[:type]).to eq("HDD")
    end

    it "maps dmi data" do
      result = mapper.call
      expect(result[:dmi][:bios][:vendor]).to eq("AMI")
      expect(result[:dmi][:system][:manufacturer]).to eq("QCT")
    end

    it "maps network_v2 data" do
      result = mapper.call
      expect(result[:network_v2][:devices].first[:name]).to eq("eth0")
    end

    it "produces output compatible with ProcessStateService" do
      result = mapper.call
      expect(result).to have_key(:host)
      expect(result).to have_key(:cpu)
      expect(result).to have_key(:memory)
      expect(result).to have_key(:disks)
      expect(result).to have_key(:network)
      expect(result).to have_key(:network_v2)
      expect(result).to have_key(:dmi)
    end

    it "handles missing optional data gracefully" do
      mapper = described_class.new(grains: grains, dmi: nil, numa: nil, network_v2: nil)
      result = mapper.call
      expect(result[:host][:hostname]).to eq("node-01")
      expect(result[:cpu][:numa_info]).to be_nil
      expect(result[:dmi]).to eq({})
      expect(result[:network_v2]).to eq({})
    end

    it "handles string error responses for optional data" do
      mapper = described_class.new(
        grains: grains,
        dmi: "'inventory.collect_dmi' is not available.",
        numa: "'inventory.collect_numa' is not available.",
        network_v2: "'inventory.collect_network_v2' is not available."
      )
      result = mapper.call
      expect(result[:host][:hostname]).to eq("node-01")
      expect(result[:cpu][:numa_info]).to be_nil
      expect(result[:dmi]).to eq({})
      expect(result[:network_v2]).to eq({})
    end
  end
end
