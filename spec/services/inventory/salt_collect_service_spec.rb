require "rails_helper"

RSpec.describe Inventory::SaltCollectService do
  let(:node) { create(:node, hostname: "node-01") }
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(node, salt_client: salt_client) }

  let(:grains_response) do
    {
      "host" => "node-01",
      "fqdn" => "node-01.cluster.local",
      "ip4_interfaces" => { "eth0" => [ "10.0.1.1" ] },
      "cpuarch" => "x86_64",
      "kernel" => "Linux",
      "kernelrelease" => "5.15.0",
      "os" => "CentOS",
      "osrelease" => "8.5",
      "cpu_model" => "Intel Xeon Gold 6248",
      "num_cpus" => 40,
      "mem_total" => 256000,
      "disks" => [ "sda" ],
      "SSDs" => [ "sda" ],
      "gpus" => []
    }
  end

  let(:dmi_response) do
    { "bios" => { "vendor" => "AMI" }, "system" => {}, "baseboard" => {} }
  end

  let(:numa_response) do
    { "node_count" => 2, "nodes" => {} }
  end

  let(:network_v2_response) do
    { "devices" => [] }
  end

  let(:cpu_topology_response) do
    { "sockets" => 2, "cores_per_socket" => 20, "threads_per_core" => 2, "flags" => [ "avx2" ] }
  end

  describe "#call" do
    before do
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items")
        .and_return(grains_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_dmi")
        .and_return(dmi_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_numa")
        .and_return(numa_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_network_v2")
        .and_return(network_v2_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_cpu")
        .and_return(cpu_topology_response)
    end

    it "collects inventory and creates a node state" do
      result = service.call
      expect(result.success?).to be true
    end

    it "delegates to ProcessStateService with mapped data" do
      mock_result = Inventory::ProcessStateService::Result.new(
        success: true, state_created: true, node_state: nil, error: nil, error_code: nil
      )
      mock_service = instance_double(Inventory::ProcessStateService, call: mock_result)
      expect(Inventory::ProcessStateService).to receive(:new).with(
        hash_including(node_id: node.id, raw_json: hash_including(:host, :cpu, :memory))
      ).and_return(mock_service)

      service.call
    end

    it "falls back to lscpu when custom CPU module unavailable" do
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_cpu")
        .and_raise(SaltApiClient::ApiError, "module not available")
      allow(salt_client).to receive(:run)
        .with("node-01", "cmd.run", arg: [ "lscpu" ])
        .and_return("Socket(s):             2\nCore(s) per socket:    20\n")

      result = service.call
      expect(result.success?).to be true
    end

    it "skips lscpu when custom CPU module succeeds" do
      expect(salt_client).not_to receive(:run).with("node-01", "cmd.run", arg: [ "lscpu" ])

      service.call
    end

    it "handles SaltApiClient::TargetUnreachable" do
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items")
        .and_raise(SaltApiClient::TargetUnreachable, "Minion not responding")

      result = service.call
      expect(result.success?).to be false
      expect(result.error).to include("not responding")
    end

    it "handles SaltApiClient::TimeoutError" do
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items")
        .and_raise(SaltApiClient::TimeoutError, "Connection timed out")

      result = service.call
      expect(result.success?).to be false
      expect(result.error).to include("timed out")
    end
  end
end
