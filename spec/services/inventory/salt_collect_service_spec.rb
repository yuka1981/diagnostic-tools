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

  let(:meminfo_response) do
    { "MemTotal" => 2113698482, "MemAvailable" => 1900000000 }
  end

  let(:disk_usage_response) do
    {
      "/" => { "filesystem" => "/dev/sda2", "1K-blocks" => "50000000", "used" => "20000000", "available" => "30000000", "capacity" => "40%" },
      "/boot" => { "filesystem" => "/dev/sda1", "1K-blocks" => "1000000", "used" => "200000", "available" => "800000", "capacity" => "20%" }
    }
  end

  let(:disk_blkid_response) do
    {
      "/dev/sda1" => { "TYPE" => "ext4", "UUID" => "abc-123" },
      "/dev/sda2" => { "TYPE" => "xfs", "UUID" => "def-456" }
    }
  end

  let(:salt_timeout) { Inventory::SaltCollectService::SALT_TIMEOUT }

  describe "#call" do
    before do
      allow(salt_client).to receive(:run_async)
        .with("node-01", "saltutil.sync_modules")
        .and_return("20260201000000000001")
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items", timeout: salt_timeout)
        .and_return(grains_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_dmi", timeout: salt_timeout)
        .and_return(dmi_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_numa", timeout: salt_timeout)
        .and_return(numa_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_network_v2", timeout: salt_timeout)
        .and_return(network_v2_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_cpu", timeout: salt_timeout)
        .and_return(cpu_topology_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_meminfo", timeout: salt_timeout)
        .and_return(meminfo_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "disk.usage", timeout: salt_timeout)
        .and_return(disk_usage_response)
      allow(salt_client).to receive(:run)
        .with("node-01", "disk.blkid", timeout: salt_timeout)
        .and_return(disk_blkid_response)
    end

    it "collects inventory and creates a node state" do
      result = service.call
      expect(result.success?).to be true
    end

    it "fires async module sync before collecting" do
      expect(salt_client).to receive(:run_async)
        .with("node-01", "saltutil.sync_modules")
      service.call
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

    it "falls back to lscpu when custom CPU module raises ApiError" do
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_cpu", timeout: salt_timeout)
        .and_raise(SaltApiClient::ApiError, "module not available")
      allow(salt_client).to receive(:run)
        .with("node-01", "cmd.run", arg: [ "lscpu" ], timeout: salt_timeout)
        .and_return("Socket(s):             2\nCore(s) per socket:    20\n")

      result = service.call
      expect(result.success?).to be true
    end

    it "falls back to lscpu when custom CPU module raises TargetUnreachable" do
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_cpu", timeout: salt_timeout)
        .and_raise(SaltApiClient::TargetUnreachable, "Minion did not return a result")
      allow(salt_client).to receive(:run)
        .with("node-01", "cmd.run", arg: [ "lscpu" ], timeout: salt_timeout)
        .and_return("Socket(s):             2\nCore(s) per socket:    20\n")

      result = service.call
      expect(result.success?).to be true
    end

    it "falls back to lscpu when custom CPU module returns string error" do
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_cpu", timeout: salt_timeout)
        .and_return("'inventory.collect_cpu' is not available.")
      allow(salt_client).to receive(:run)
        .with("node-01", "cmd.run", arg: [ "lscpu" ], timeout: salt_timeout)
        .and_return("Socket(s):             2\nCore(s) per socket:    20\n")

      result = service.call
      expect(result.success?).to be true
    end

    it "skips lscpu when custom CPU module succeeds" do
      expect(salt_client).not_to receive(:run).with("node-01", "cmd.run", arg: [ "lscpu" ], timeout: salt_timeout)

      service.call
    end

    it "degrades gracefully when meminfo module fails with ApiError" do
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_meminfo", timeout: salt_timeout)
        .and_raise(SaltApiClient::ApiError, "module not available")

      result = service.call
      expect(result.success?).to be true
    end

    it "degrades gracefully when meminfo module fails with TargetUnreachable" do
      allow(salt_client).to receive(:run)
        .with("node-01", "inventory.collect_meminfo", timeout: salt_timeout)
        .and_raise(SaltApiClient::TargetUnreachable, "Minion did not return a result")

      result = service.call
      expect(result.success?).to be true
    end

    it "continues when async module sync fails" do
      allow(salt_client).to receive(:run_async)
        .with("node-01", "saltutil.sync_modules")
        .and_raise(SaltApiClient::ApiError, "No job ID returned")

      result = service.call
      expect(result.success?).to be true
    end

    it "handles SaltApiClient::TargetUnreachable on grains.items" do
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items", timeout: salt_timeout)
        .and_raise(SaltApiClient::TargetUnreachable, "Minion not responding")

      result = service.call
      expect(result.success?).to be false
      expect(result.error).to include("not responding")
    end

    it "handles SaltApiClient::TimeoutError" do
      allow(salt_client).to receive(:run)
        .with("node-01", "grains.items", timeout: salt_timeout)
        .and_raise(SaltApiClient::TimeoutError, "Connection timed out")

      result = service.call
      expect(result.success?).to be false
      expect(result.error).to include("timed out")
    end

    it "degrades gracefully when disk.usage fails with ApiError" do
      allow(salt_client).to receive(:run)
        .with("node-01", "disk.usage", timeout: salt_timeout)
        .and_raise(SaltApiClient::ApiError, "module not available")

      result = service.call
      expect(result.success?).to be true
    end

    it "degrades gracefully when disk.usage fails with TargetUnreachable" do
      allow(salt_client).to receive(:run)
        .with("node-01", "disk.usage", timeout: salt_timeout)
        .and_raise(SaltApiClient::TargetUnreachable, "Minion did not return a result")

      result = service.call
      expect(result.success?).to be true
    end

    it "degrades gracefully when disk.blkid fails with ApiError" do
      allow(salt_client).to receive(:run)
        .with("node-01", "disk.blkid", timeout: salt_timeout)
        .and_raise(SaltApiClient::ApiError, "module not available")

      result = service.call
      expect(result.success?).to be true
    end
  end
end
