# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::ProcessStateService do
  describe "#call" do
    let(:node) { create(:node) }
    let(:raw_json) do
      {
        cpu_info: { "model" => "Intel Xeon", "cores" => 16 },
        mem_info: { "total" => 64.gigabytes },
        disk_info: [ { "device" => "/dev/sda", "total" => 500.gigabytes } ],
        net_info: [ { "interface" => "eth0", "ip" => "192.168.1.100" } ]
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

        expect(state.cpu_info).to eq(raw_json[:cpu_info])
        expect(state.mem_info).to eq(raw_json[:mem_info])
        expect(state.disk_info).to eq(raw_json[:disk_info])
        expect(state.net_info).to eq(raw_json[:net_info])
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
          cpu_info: raw_json[:cpu_info],
          mem_info: raw_json[:mem_info],
          disk_info: raw_json[:disk_info],
          net_info: raw_json[:net_info],
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
        expect(new_state.cpu_info).to eq(raw_json[:cpu_info])
      end

      it "updates node last_seen_at" do
        expect { service.call }.to change { node.reload.last_seen_at }
      end
    end

    context "with string keys in raw_json" do
      let(:raw_json) do
        {
          "cpu_info" => { "model" => "Intel Xeon", "cores" => 16 },
          "mem_info" => { "total" => 64.gigabytes },
          "disk_info" => [ { "device" => "/dev/sda" } ],
          "net_info" => [ { "interface" => "eth0" } ]
        }
      end

      it "handles string keys correctly" do
        expect { service.call }.to change(NodeState, :count).by(1)
      end
    end

    context "with partial raw_json (missing some info)" do
      let(:raw_json) do
        {
          cpu_info: { "model" => "Intel Xeon" },
          mem_info: {}
        }
      end

      it "creates NodeState with defaults for missing fields" do
        result = service.call
        state = result.node_state

        expect(state.cpu_info).to eq(raw_json[:cpu_info])
        expect(state.mem_info).to eq({})
        expect(state.disk_info).to eq([])
        expect(state.net_info).to eq([])
      end
    end

    context "when node does not exist" do
      subject(:service) { described_class.new(node_id: 99999, raw_json: raw_json) }

      it "returns failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to match(/not found/i)
      end

      it "does not create NodeState" do
        expect { service.call }.not_to change(NodeState, :count)
      end
    end

    context "when raw_json is nil" do
      let(:raw_json) { nil }

      it "returns failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to match(/empty/i)
      end
    end

    context "when raw_json is empty hash" do
      let(:raw_json) { {} }

      it "creates NodeState with empty content" do
        result = service.call
        expect(result.success?).to be true
        expect(result.node_state.cpu_info).to eq({})
      end
    end

    context "when finding node by hostname" do
      subject(:service) { described_class.new(hostname: node.hostname, raw_json: raw_json) }

      it "creates a new NodeState" do
        expect { service.call }.to change(NodeState, :count).by(1)
      end

      it "returns success result" do
        result = service.call
        expect(result.success?).to be true
      end
    end

    context "when hostname does not exist" do
      subject(:service) { described_class.new(hostname: "nonexistent", raw_json: raw_json) }

      it "returns failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to match(/not found/i)
      end
    end
  end
end
