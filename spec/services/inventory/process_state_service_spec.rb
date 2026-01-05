# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::ProcessStateService do
  describe "#call" do
    let(:node) { create(:node) }
    let(:raw_json) do
      {
        host: { "os" => "linux", "platform" => "ubuntu" },
        cpu: { "model" => "Intel Xeon", "cores" => 16 },
        memory: { "total" => 64.gigabytes },
        disks: [ { "device" => "/dev/sda", "total" => 500.gigabytes } ],
        network: [ { "interface" => "eth0", "ip" => "192.168.1.100" } ]
      }
    end

    subject(:service) { described_class.new(node_id: node.id, raw_json: raw_json) }

    context "when node has no previous state" do
      it "creates a new NodeState" do
        expect { service.call }.to change(NodeState, :count).by(1)
      end

      it "returns success result with state_created true" do
        result = service.call
        expect(result.success?).to be true
        expect(result.state_created).to be true
        expect(result.node_state).to be_a(NodeState)
      end

      it "creates NodeState with correct attributes" do
        result = service.call
        state = result.node_state

        expect(state.host_info).to eq(raw_json[:host])
        expect(state.cpu_info).to eq(raw_json[:cpu])
        expect(state.mem_info).to eq(raw_json[:memory])
        expect(state.disk_info).to eq(raw_json[:disks])
        expect(state.net_info).to eq(raw_json[:network])
        expect(state.captured_at).to be_present
      end

      it "updates node last_seen_at" do
        expect { service.call }.to change { node.reload.last_seen_at }
      end
    end

    context "when node has existing state with same content" do
      let!(:existing_state) do
        create(:node_state,
          node: node,
          host_info: raw_json[:host],
          cpu_info: raw_json[:cpu],
          mem_info: raw_json[:memory],
          disk_info: raw_json[:disks],
          net_info: raw_json[:network],
          captured_at: 1.hour.ago
        )
      end

      it "does not create a new NodeState" do
        expect { service.call }.not_to change(NodeState, :count)
      end

      it "returns success result with state_created false" do
        result = service.call
        expect(result.success?).to be true
        expect(result.state_created).to be false
        expect(result.node_state).to eq(existing_state)
      end

      it "updates node last_seen_at" do
        expect { service.call }.to change { node.reload.last_seen_at }
      end
    end

    context "when node has existing state with different content" do
      let!(:existing_state) do
        create(:node_state,
          node: node,
          host_info: { "os" => "linux" },
          cpu_info: { "model" => "Different CPU", "cores" => 8 },
          mem_info: { "total" => 32.gigabytes },
          disk_info: [],
          net_info: [],
          captured_at: 1.hour.ago
        )
      end

      it "creates a new NodeState" do
        expect { service.call }.to change(NodeState, :count).by(1)
      end

      it "returns success result with state_created true" do
        result = service.call
        expect(result.success?).to be true
        expect(result.state_created).to be true
      end

      it "creates NodeState with new content" do
        result = service.call
        new_state = result.node_state

        expect(new_state.id).not_to eq(existing_state.id)
        expect(new_state.host_info).to eq(raw_json[:host])
        expect(new_state.cpu_info).to eq(raw_json[:cpu])
      end

      it "updates node last_seen_at" do
        expect { service.call }.to change { node.reload.last_seen_at }
      end
    end

    context "with string keys in raw_json" do
      let(:raw_json) do
        {
          "host" => { "os" => "linux" },
          "cpu" => { "model" => "Intel Xeon", "cores" => 16 },
          "memory" => { "total" => 64.gigabytes },
          "disks" => [ { "device" => "/dev/sda" } ],
          "network" => [ { "interface" => "eth0" } ]
        }
      end

      it "handles string keys correctly" do
        expect { service.call }.to change(NodeState, :count).by(1)
      end
    end

    context "with partial raw_json (missing some info)" do
      let(:raw_json) { { "host" => { "os" => "linux" } } }

      it "creates NodeState with defaults for missing fields" do
        result = service.call
        state = result.node_state

        expect(state.host_info).to eq(raw_json["host"])
        expect(state.cpu_info).to eq({})
        expect(state.mem_info).to eq({})
        expect(state.disk_info).to eq([])
        expect(state.net_info).to eq([])
      end
    end

    context "when raw_json is nil" do
      let(:raw_json) { nil }

      it "returns failure result with bad_request error code" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error_code).to eq(:bad_request)
      end
    end

    context "when raw_json is empty hash" do
      let(:raw_json) { {} }

      it "creates NodeState with empty content" do
        expect { service.call }.to change(NodeState, :count).by(1)
      end
    end

    context "when node does not exist" do
      subject(:service) { described_class.new(node_id: 999_999, raw_json: raw_json) }

      it "returns failure result with not_found error code" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error_code).to eq(:not_found)
      end

      it "does not create NodeState" do
        expect { service.call }.not_to change(NodeState, :count)
      end
    end

    context "when finding node by hostname" do
      subject(:service) { described_class.new(hostname: node.hostname, raw_json: raw_json) }

      it "returns success result" do
        result = service.call
        expect(result.success?).to be true
      end

      it "creates a new NodeState" do
        expect { service.call }.to change(NodeState, :count).by(1)
      end
    end

    context "when hostname does not exist" do
      subject(:service) { described_class.new(hostname: "non-existent", raw_json: raw_json) }

      it "returns failure result with not_found error code" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error_code).to eq(:not_found)
      end
    end

    context "when neither node_id nor hostname is provided" do
      it "raises an ArgumentError" do
        expect { described_class.new(raw_json: raw_json) }.to raise_error(ArgumentError)
      end
    end
  end
end