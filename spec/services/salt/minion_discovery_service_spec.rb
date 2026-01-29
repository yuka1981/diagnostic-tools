# frozen_string_literal: true

require "rails_helper"

RSpec.describe Salt::MinionDiscoveryService do
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) { described_class.new(salt_client: salt_client) }

  describe "#call" do
    let!(:existing_node) { create(:node, hostname: "node-01") }

    let(:minion_data) do
      {
        "node-01" => {
          "os" => "Rocky", "osrelease" => "8.9", "cpuarch" => "x86_64",
          "ipv4" => [ "127.0.0.1", "192.168.1.10" ],
          "kernelrelease" => "4.18.0-513.el8.x86_64",
          "cpu_model" => "Intel Xeon Gold 6248R",
          "mem_total" => 32768, "num_cpus" => 48
        },
        "node-02" => {
          "os" => "Rocky", "osrelease" => "8.9", "cpuarch" => "x86_64",
          "ipv4" => [ "127.0.0.1", "192.168.1.11" ],
          "kernelrelease" => "4.18.0-513.el8.x86_64",
          "cpu_model" => "Intel Xeon Gold 6248R",
          "mem_total" => 65536, "num_cpus" => 96
        },
        "node-03" => {
          "os" => "Ubuntu", "osrelease" => "22.04", "cpuarch" => "aarch64",
          "ipv4" => [ "127.0.0.1", "10.0.0.5" ],
          "kernelrelease" => "5.15.0-91-generic",
          "cpu_model" => "Ampere Altra Q80-30",
          "mem_total" => 131072, "num_cpus" => 80
        }
      }
    end

    before do
      allow(salt_client).to receive(:get_minions).and_return(minion_data)
    end

    it "returns success" do
      result = service.call
      expect(result).to be_success
    end

    it "identifies existing nodes" do
      result = service.call
      expect(result.existing).to eq([ "node-01" ])
    end

    it "discovers new nodes" do
      result = service.call
      hostnames = result.discovered.map { |d| d[:hostname] }
      expect(hostnames).to contain_exactly("node-02", "node-03")
    end

    it "extracts grains into discovery records" do
      result = service.call
      node_02 = result.discovered.find { |d| d[:hostname] == "node-02" }

      expect(node_02[:ip]).to eq("192.168.1.11")
      expect(node_02[:arch]).to eq("x86_64")
      expect(node_02[:os]).to eq("Rocky")
      expect(node_02[:os_release]).to eq("8.9")
      expect(node_02[:kernel]).to eq("4.18.0-513.el8.x86_64")
      expect(node_02[:cpu_model]).to eq("Intel Xeon Gold 6248R")
      expect(node_02[:mem_total]).to eq(65536)
      expect(node_02[:num_cpus]).to eq(96)
    end

    it "excludes 127.0.0.1 from IP selection" do
      result = service.call
      node_03 = result.discovered.find { |d| d[:hostname] == "node-03" }
      expect(node_03[:ip]).to eq("10.0.0.5")
    end

    context "when all minions are already registered" do
      let(:minion_data) { { "node-01" => { "os" => "Rocky" } } }

      it "returns empty discovered list" do
        result = service.call
        expect(result.discovered).to be_empty
      end

      it "returns existing count" do
        result = service.call
        expect(result.existing).to eq([ "node-01" ])
      end
    end

    context "when Salt API fails" do
      before do
        allow(salt_client).to receive(:get_minions)
          .and_raise(SaltApiClient::ApiError, "connection refused")
      end

      it "returns failure" do
        result = service.call
        expect(result).not_to be_success
      end

      it "includes error message" do
        result = service.call
        expect(result.error).to eq("connection refused")
      end

      it "returns empty lists" do
        result = service.call
        expect(result.discovered).to eq([])
        expect(result.existing).to eq([])
      end
    end

    context "when Salt API returns empty" do
      before do
        allow(salt_client).to receive(:get_minions).and_return({})
      end

      it "returns success with empty results" do
        result = service.call
        expect(result).to be_success
        expect(result.discovered).to be_empty
        expect(result.existing).to be_empty
      end
    end
  end
end
