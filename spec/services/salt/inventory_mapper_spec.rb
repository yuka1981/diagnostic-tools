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

    it "handles cpulist string format from custom Salt module" do
      numa_cpulist = {
        "node_count" => 2,
        "nodes" => {
          "0" => { "cpulist" => "0-19,40-59", "memory_kb" => 131072000 },
          "1" => { "cpulist" => "20-39,60-79", "memory_kb" => 131072000 }
        }
      }
      mapper = described_class.new(grains: grains, numa: numa_cpulist)
      result = mapper.call
      expect(result[:cpu][:numa_info]["0"]).to eq("0-19,40-59")
      expect(result[:cpu][:numa_info]["1"]).to eq("20-39,60-79")
    end

    it "maps CPU topology from custom Salt module" do
      cpu_topo = {
        "sockets" => 2,
        "cores_per_socket" => 20,
        "threads_per_core" => 2,
        "flags" => [ "avx", "avx2", "avx512f", "sse4_1", "sse4_2" ]
      }
      mapper = described_class.new(grains: grains, cpu_topology: cpu_topo)
      result = mapper.call
      expect(result[:cpu][:sockets]).to eq(2)
      expect(result[:cpu][:cores_per_socket]).to eq(20)
      expect(result[:cpu][:threads_per_core]).to eq(2)
      expect(result[:cpu][:flags]).to eq([ "avx", "avx2", "avx512f", "sse4_1", "sse4_2" ])
    end

    it "parses lscpu output as fallback for CPU topology" do
      lscpu_output = <<~LSCPU
        Architecture:          x86_64
        CPU op-mode(s):        32-bit, 64-bit
        CPU(s):                80
        Thread(s) per core:    2
        Core(s) per socket:    20
        Socket(s):             2
        NUMA node(s):          2
        Vendor ID:             GenuineIntel
        Flags:                 avx avx2 avx512f sse4_1 sse4_2
      LSCPU
      mapper = described_class.new(grains: grains, lscpu: lscpu_output)
      result = mapper.call
      expect(result[:cpu][:sockets]).to eq(2)
      expect(result[:cpu][:cores_per_socket]).to eq(20)
      expect(result[:cpu][:threads_per_core]).to eq(2)
      expect(result[:cpu][:numa_nodes]).to eq(2)
      expect(result[:cpu][:flags]).to eq([ "avx", "avx2", "avx512f", "sse4_1", "sse4_2" ])
    end

    it "prefers custom CPU module over lscpu fallback" do
      cpu_topo = { "sockets" => 4, "cores_per_socket" => 28 }
      lscpu_output = "Socket(s):             2\nCore(s) per socket:    20\n"
      mapper = described_class.new(grains: grains, cpu_topology: cpu_topo, lscpu: lscpu_output)
      result = mapper.call
      expect(result[:cpu][:sockets]).to eq(4)
      expect(result[:cpu][:cores_per_socket]).to eq(28)
    end

    it "uses NUMA nodes from lscpu when custom NUMA module unavailable" do
      lscpu_output = "Socket(s):             2\nNUMA node(s):          4\n"
      mapper = described_class.new(grains: grains, numa: nil, lscpu: lscpu_output)
      result = mapper.call
      expect(result[:cpu][:numa_nodes]).to eq(4)
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

    it "builds DMI fallback from grains when custom module unavailable" do
      grains_with_dmi = grains.merge(
        "manufacturer" => "Dell Inc.",
        "productname" => "PowerEdge R750",
        "serialnumber" => "ABC1234",
        "uuid" => "4c4c4544-0044-4810-8031-c7c04f323432",
        "biosversion" => "2.13.0",
        "biosreleasedate" => "06/15/2024"
      )
      mapper = described_class.new(grains: grains_with_dmi, dmi: nil)
      result = mapper.call
      expect(result[:dmi][:system][:manufacturer]).to eq("Dell Inc.")
      expect(result[:dmi][:system][:product_name]).to eq("PowerEdge R750")
      expect(result[:dmi][:system][:serial_number]).to eq("ABC1234")
      expect(result[:dmi][:system][:uuid]).to eq("4c4c4544-0044-4810-8031-c7c04f323432")
      expect(result[:dmi][:bios][:version]).to eq("2.13.0")
      expect(result[:dmi][:bios][:release_date]).to eq("06/15/2024")
    end

    it "prefers custom DMI module data over grains fallback" do
      grains_with_dmi = grains.merge("manufacturer" => "Grains Manufacturer")
      mapper = described_class.new(grains: grains_with_dmi, dmi: dmi_data)
      result = mapper.call
      expect(result[:dmi][:system][:manufacturer]).to eq("QCT")
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

    it "extracts virtualization from lscpu" do
      lscpu_output = <<~LSCPU
        Socket(s):             2
        Virtualization:        VT-x
      LSCPU
      mapper = described_class.new(grains: grains, lscpu: lscpu_output)
      result = mapper.call
      expect(result[:cpu][:virtualization]).to eq("VT-x")
    end

    it "extracts cache info with short lscpu keys" do
      lscpu_output = <<~LSCPU
        Socket(s):             2
        L1d:                   2.6 MiB (56 instances)
        L1i:                   1.8 MiB (56 instances)
        L2:                    112 MiB (56 instances)
        L3:                    105 MiB (2 instances)
      LSCPU
      mapper = described_class.new(grains: grains, lscpu: lscpu_output)
      result = mapper.call
      expect(result[:cpu][:l1d_cache]).to eq("2.6 MiB (56 instances)")
      expect(result[:cpu][:l1i_cache]).to eq("1.8 MiB (56 instances)")
      expect(result[:cpu][:l2_cache]).to eq("112 MiB (56 instances)")
      expect(result[:cpu][:l3_cache]).to eq("105 MiB (2 instances)")
    end

    it "extracts cache info with long lscpu keys" do
      lscpu_output = <<~LSCPU
        Socket(s):             2
        L1d cache:             64K
        L1i cache:             64K
        L2 cache:              512K
        L3 cache:              16384K
      LSCPU
      mapper = described_class.new(grains: grains, lscpu: lscpu_output)
      result = mapper.call
      expect(result[:cpu][:l1d_cache]).to eq("64K")
      expect(result[:cpu][:l1i_cache]).to eq("64K")
      expect(result[:cpu][:l2_cache]).to eq("512K")
      expect(result[:cpu][:l3_cache]).to eq("16384K")
    end

    it "falls back to lscpu NUMA mappings when custom module unavailable" do
      lscpu_output = <<~LSCPU
        Socket(s):             2
        NUMA node(s):          2
        NUMA node0 CPU(s):     0-19,40-59
        NUMA node1 CPU(s):     20-39,60-79
      LSCPU
      mapper = described_class.new(grains: grains, numa: nil, lscpu: lscpu_output)
      result = mapper.call
      expect(result[:cpu][:numa_info]).to eq({
        "0" => "0-19,40-59",
        "1" => "20-39,60-79"
      })
    end

    it "maps memory available from meminfo" do
      meminfo = { "MemTotal" => 2113698482, "MemAvailable" => 1900000000 }
      mapper = described_class.new(grains: grains, meminfo: meminfo)
      result = mapper.call
      expect(result[:memory][:available]).to eq(1900000000 * 1024)
      expect(result[:memory][:total]).to eq(256000 * 1024 * 1024)
    end

    it "omits available when meminfo is nil" do
      mapper = described_class.new(grains: grains, meminfo: nil)
      result = mapper.call
      expect(result[:memory]).not_to have_key(:available)
      expect(result[:memory][:total]).to eq(256000 * 1024 * 1024)
    end

    it "maps DMI memory devices array through dmi_info" do
      dmi_with_memory = dmi_data.merge(
        "memory" => [
          { "size" => "32 GB", "type" => "DDR4", "speed" => "3200 MT/s", "locator" => "DIMM_A0" },
          { "size" => "32 GB", "type" => "DDR4", "speed" => "3200 MT/s", "locator" => "DIMM_B0" }
        ]
      )
      mapper = described_class.new(grains: grains, dmi: dmi_with_memory)
      result = mapper.call
      expect(result[:dmi][:memory]).to be_an(Array)
      expect(result[:dmi][:memory].length).to eq(2)
      expect(result[:dmi][:memory].first[:size]).to eq("32 GB")
      expect(result[:dmi][:memory].first[:locator]).to eq("DIMM_A0")
    end

    it "normalizes configured_memory_speed to configured_speed in DMI memory" do
      dmi_with_memory = dmi_data.merge(
        "memory" => [
          { "size" => "32 GB", "configured_memory_speed" => "2933 MT/s" }
        ]
      )
      mapper = described_class.new(grains: grains, dmi: dmi_with_memory)
      result = mapper.call
      expect(result[:dmi][:memory].first[:configured_speed]).to eq("2933 MT/s")
      expect(result[:dmi][:memory].first).not_to have_key(:configured_memory_speed)
    end

    it "falls back to grains when DMI module returns error dict" do
      grains_with_dmi = grains.merge(
        "manufacturer" => "Dell Inc.",
        "productname" => "PowerEdge R750",
        "biosversion" => "2.13.0"
      )
      error_dmi = { "error" => "dmidecode not found" }
      mapper = described_class.new(grains: grains_with_dmi, dmi: error_dmi)
      result = mapper.call
      expect(result[:dmi][:system][:manufacturer]).to eq("Dell Inc.")
      expect(result[:dmi][:bios][:version]).to eq("2.13.0")
      expect(result[:dmi]).not_to have_key(:error)
    end

    it "custom NUMA module takes precedence over lscpu NUMA mappings" do
      lscpu_output = <<~LSCPU
        Socket(s):             2
        NUMA node0 CPU(s):     0-19,40-59
        NUMA node1 CPU(s):     20-39,60-79
      LSCPU
      mapper = described_class.new(grains: grains, numa: numa_data, lscpu: lscpu_output)
      result = mapper.call
      expect(result[:cpu][:numa_info]).to eq({
        "0" => "0-3",
        "1" => "4-7"
      })
    end
  end
end
