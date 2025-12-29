# frozen_string_literal: true

require "rails_helper"

RSpec.describe NodeState, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:captured_at) }
  end

  describe "factory" do
    it "creates a valid node_state" do
      node_state = build(:node_state)
      expect(node_state).to be_valid
    end

    it "creates a node_state with cpu_info" do
      node_state = build(:node_state, :with_cpu_info)
      expect(node_state.cpu_info).to include("model", "cores", "threads")
    end

    it "creates a node_state with mem_info" do
      node_state = build(:node_state, :with_mem_info)
      expect(node_state.mem_info).to include("total", "free")
    end

    it "creates a node_state with disk_info" do
      node_state = build(:node_state, :with_disk_info)
      expect(node_state.disk_info).to be_an(Array)
    end

    it "creates a node_state with net_info" do
      node_state = build(:node_state, :with_net_info)
      expect(node_state.net_info).to be_an(Array)
    end

    it "creates a complete node_state with all info" do
      node_state = build(:node_state, :complete)
      expect(node_state.cpu_info).to be_present
      expect(node_state.mem_info).to be_present
      expect(node_state.disk_info).to be_present
      expect(node_state.net_info).to be_present
    end
  end

  describe "scopes" do
    let(:node) { create(:node) }
    let!(:old_state) { create(:node_state, node: node, captured_at: 2.days.ago) }
    let!(:recent_state) { create(:node_state, node: node, captured_at: 1.day.ago) }
    let!(:latest_state) { create(:node_state, node: node, captured_at: 1.hour.ago) }

    describe ".latest_first" do
      it "orders by captured_at descending" do
        expect(NodeState.latest_first.to_a).to eq([ latest_state, recent_state, old_state ])
      end
    end

    describe ".for_node" do
      let(:other_node) { create(:node) }
      let!(:other_state) { create(:node_state, node: other_node) }

      it "returns states for specified node only" do
        expect(NodeState.for_node(node)).to match_array([ old_state, recent_state, latest_state ])
        expect(NodeState.for_node(node)).not_to include(other_state)
      end
    end
  end

  describe "#content_hash" do
    it "generates consistent hash for same content" do
      state1 = build(:node_state, :complete)
      state2 = build(:node_state,
        cpu_info: state1.cpu_info,
        mem_info: state1.mem_info,
        disk_info: state1.disk_info,
        net_info: state1.net_info
      )
      expect(state1.content_hash).to eq(state2.content_hash)
    end

    it "generates different hash for different content" do
      state1 = build(:node_state, :with_cpu_info)
      state2 = build(:node_state, :with_cpu_info, cpu_info: { "model" => "Different CPU" })
      expect(state1.content_hash).not_to eq(state2.content_hash)
    end
  end

  describe "#same_content_as?" do
    let(:state1) { build(:node_state, :complete) }

    it "returns true for same content" do
      state2 = build(:node_state,
        cpu_info: state1.cpu_info,
        mem_info: state1.mem_info,
        disk_info: state1.disk_info,
        net_info: state1.net_info
      )
      expect(state1.same_content_as?(state2)).to be true
    end

    it "returns false for different content" do
      state2 = build(:node_state, cpu_info: { "different" => "content" })
      expect(state1.same_content_as?(state2)).to be false
    end

    it "returns false when comparing with nil" do
      expect(state1.same_content_as?(nil)).to be false
    end

    it "returns false when comparing with non-NodeState object" do
      expect(state1.same_content_as?("string")).to be false
      expect(state1.same_content_as?(123)).to be false
      expect(state1.same_content_as?({})).to be false
    end
  end

  describe "Node#node_states association" do
    let(:node) { create(:node) }

    it "allows node to have multiple states" do
      create_list(:node_state, 3, node: node)
      expect(node.node_states.count).to eq(3)
    end

    it "destroys states when node is destroyed" do
      create_list(:node_state, 2, node: node)
      expect { node.destroy }.to change(NodeState, :count).by(-2)
    end
  end

  describe "Node#current_state" do
    let(:node) { create(:node) }

    context "when node has states" do
      let!(:old_state) { create(:node_state, node: node, captured_at: 1.day.ago) }
      let!(:latest_state) { create(:node_state, node: node, captured_at: 1.hour.ago) }

      it "returns the most recent state" do
        expect(node.current_state).to eq(latest_state)
      end
    end

    context "when node has no states" do
      it "returns nil" do
        expect(node.current_state).to be_nil
      end
    end
  end
end
