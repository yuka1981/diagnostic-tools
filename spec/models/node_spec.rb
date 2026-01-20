# frozen_string_literal: true

require "rails_helper"

RSpec.describe Node, type: :model do
  describe "validations" do
    subject { build(:node) }

    it { is_expected.to validate_presence_of(:hostname) }
    it { is_expected.to validate_uniqueness_of(:hostname) }
    it { is_expected.to validate_length_of(:hostname).is_at_most(255) }

    it { is_expected.to allow_value("192.168.1.1").for(:ip) }
    it { is_expected.to allow_value("10.0.0.1").for(:ip) }
    it { is_expected.to allow_value("2001:db8::1").for(:ip) }
    it { is_expected.to allow_value(nil).for(:ip) }
    it { is_expected.to allow_value("").for(:ip) }
    it { is_expected.not_to allow_value("invalid-ip").for(:ip) }
    it { is_expected.not_to allow_value("999.999.999.999").for(:ip) }

    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_presence_of(:source) }

    describe "localhost validation" do
      it { is_expected.not_to allow_value("localhost").for(:hostname).with_message(/cannot be localhost/) }
      it { is_expected.not_to allow_value("127.0.0.1").for(:hostname).with_message(/cannot be localhost/) }
      it { is_expected.not_to allow_value("::1").for(:hostname).with_message(/cannot be localhost/) }
      it { is_expected.not_to allow_value("LOCALHOST").for(:hostname).with_message(/cannot be localhost/) }

      it { is_expected.not_to allow_value("127.0.0.1").for(:ip).with_message(/cannot be a localhost/) }
      it { is_expected.not_to allow_value("::1").for(:ip).with_message(/cannot be a localhost/) }

      it { is_expected.to allow_value("compute-001").for(:hostname) }
      it { is_expected.to allow_value("192.168.1.100").for(:ip) }
    end
  end

  describe ".localhost?" do
    it "returns true for localhost" do
      expect(Node.localhost?("localhost")).to be true
    end

    it "returns true for 127.0.0.1" do
      expect(Node.localhost?("127.0.0.1")).to be true
    end

    it "returns true for ::1" do
      expect(Node.localhost?("::1")).to be true
    end

    it "returns true for LOCALHOST (case insensitive)" do
      expect(Node.localhost?("LOCALHOST")).to be true
    end

    it "returns false for regular hostname" do
      expect(Node.localhost?("compute-001")).to be false
    end

    it "returns false for regular IP" do
      expect(Node.localhost?("192.168.1.1")).to be false
    end

    it "returns false for blank value" do
      expect(Node.localhost?("")).to be false
      expect(Node.localhost?(nil)).to be false
    end
  end

  describe "enums" do
    describe "role" do
      it "defines compute, login, and admin roles" do
        expect(Node.roles).to eq({ "compute" => 0, "login" => 1, "admin" => 2 })
      end

      it "defaults to compute role" do
        node = Node.new
        expect(node.role).to eq("compute")
      end

      it "can be set to login" do
        node = build(:node, :login)
        expect(node).to be_login
      end

      it "can be set to admin" do
        node = build(:node, :admin)
        expect(node).to be_admin
      end
    end

    describe "source" do
      it "defines manual, csv, and agent_push sources" do
        expect(Node.sources).to eq({ "manual" => 0, "csv" => 1, "agent_push" => 2 })
      end

      it "defaults to manual source" do
        node = Node.new
        expect(node.source).to eq("manual")
      end

      it "can be set to csv" do
        node = build(:node, :csv)
        expect(node).to be_csv
      end

      it "can be set to agent_push" do
        node = build(:node, :agent_push)
        expect(node).to be_agent_push
      end
    end
  end

  describe "factory" do
    it "creates a valid node" do
      node = build(:node)
      expect(node).to be_valid
    end

    it "creates a valid node with default compute role" do
      node = build(:node)
      expect(node).to be_valid
      expect(node).to be_compute
    end

    it "creates a valid node with login trait" do
      node = build(:node, :login)
      expect(node).to be_valid
      expect(node).to be_login
    end

    it "creates a valid node with admin trait" do
      node = build(:node, :admin)
      expect(node).to be_valid
      expect(node).to be_admin
    end

    it "creates a valid node with csv trait" do
      node = build(:node, :csv)
      expect(node).to be_valid
      expect(node).to be_csv
    end

    it "creates a valid node with agent_push trait" do
      node = build(:node, :agent_push)
      expect(node).to be_valid
      expect(node).to be_agent_push
    end
  end

  describe "scopes" do
    let!(:compute_nodes) { create_list(:node, 2) } # defaults to compute role
    let!(:login_node) { create(:node, :login) }
    let!(:admin_node) { create(:node, :admin) }

    it "returns only compute nodes with compute scope" do
      expect(Node.compute).to match_array(compute_nodes)
    end

    it "returns only login nodes with login scope" do
      expect(Node.login).to eq([ login_node ])
    end

    it "returns only admin nodes with admin scope" do
      expect(Node.admin).to eq([ admin_node ])
    end
  end

  describe "#online?" do
    it "returns true if last_heartbeat_at is within 2 minutes" do
      node = build(:node, last_heartbeat_at: 1.minute.ago)
      expect(node).to be_online
    end

    it "returns false if last_heartbeat_at is older than 2 minutes" do
      node = build(:node, last_heartbeat_at: 3.minutes.ago)
      expect(node).not_to be_online
    end

    it "returns false if last_heartbeat_at is nil" do
      node = build(:node, last_heartbeat_at: nil)
      expect(node).not_to be_online
    end
  end

  describe "#touch_last_seen" do
    it "updates last_seen_at to current time" do
      node = create(:node, last_seen_at: 1.hour.ago)
      expect { node.touch_last_seen }.to change { node.reload.last_seen_at }
    end
  end

  describe "#effective_api_token" do
    context "when node has direct api_token set" do
      it "returns the direct api_token" do
        node = build(:node, api_token: "direct-token-123")
        expect(node.effective_api_token).to eq("direct-token-123")
      end
    end

    context "when node has associated ApiKey" do
      it "returns the ApiKey's token" do
        api_key = create(:api_key)
        node = build(:node, api_key: api_key)
        expect(node.effective_api_token).to eq(api_key.token)
      end
    end

    context "when node has both direct api_token and associated ApiKey" do
      it "prefers the direct api_token" do
        api_key = create(:api_key)
        node = build(:node, api_token: "direct-token-456", api_key: api_key)
        expect(node.effective_api_token).to eq("direct-token-456")
      end
    end

    context "when node has neither api_token nor ApiKey" do
      it "returns nil" do
        node = build(:node, api_token: nil, api_key: nil)
        expect(node.effective_api_token).to be_nil
      end
    end

    context "when node has empty api_token string and associated ApiKey" do
      it "returns the ApiKey's token" do
        api_key = create(:api_key)
        node = build(:node, api_token: "", api_key: api_key)
        expect(node.effective_api_token).to eq(api_key.token)
      end
    end
  end

  describe "#busy?" do
    let(:node) { create(:node) }
    let(:recipe) { create(:benchmark_recipe) }

    context "when node has no benchmark runs" do
      it "returns false" do
        expect(node.busy?).to be false
      end
    end

    context "when node has only completed benchmark runs" do
      before do
        create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :success)
        create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :failed)
        create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :cancelled)
      end

      it "returns false" do
        expect(node.busy?).to be false
      end
    end

    context "when node has a pending benchmark run" do
      before do
        create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending)
      end

      it "returns true" do
        expect(node.busy?).to be true
      end
    end

    context "when node has a running benchmark run" do
      before do
        create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :running)
      end

      it "returns true" do
        expect(node.busy?).to be true
      end
    end

    context "when node has both completed and pending runs" do
      before do
        create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :success)
        create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending)
      end

      it "returns true" do
        expect(node.busy?).to be true
      end
    end
  end

  describe "rack associations" do
    it { is_expected.to belong_to(:rack).optional }
  end

  describe "rack_face enum" do
    it "defines front and rear faces with prefix" do
      expect(Node.rack_faces).to eq({ "front" => 0, "rear" => 1 })
    end

    it "defaults to front face" do
      node = Node.new
      expect(node.rack_face).to eq("front")
    end

    it "provides prefixed methods for front" do
      node = build(:node, rack_face: :front)
      expect(node).to be_rack_face_front
    end

    it "provides prefixed methods for rear" do
      node = build(:node, rack_face: :rear)
      expect(node).to be_rack_face_rear
    end
  end

  describe "#cpu_summary" do
    context "when node has current_state with cpu_info" do
      it "returns formatted CPU summary" do
        node = create(:node)
        create(:node_state, node: node, cpu_info: {
          "model_name" => "Intel(R) Xeon(R) Gold 6330 CPU @ 2.00GHz",
          "sockets" => 2,
          "cores" => 56
        })

        expect(node.cpu_summary).to eq("2x Xeon Gold 6330")
      end

      it "handles AMD processors" do
        node = create(:node)
        create(:node_state, node: node, cpu_info: {
          "model_name" => "AMD EPYC 7763 64-Core Processor",
          "sockets" => 2,
          "cores" => 128
        })

        expect(node.cpu_summary).to eq("2x EPYC 7763 64-Core")
      end

      it "handles single socket" do
        node = create(:node)
        create(:node_state, node: node, cpu_info: {
          "model_name" => "Intel(R) Core(TM) i9-12900K CPU @ 3.20GHz",
          "sockets" => 1,
          "cores" => 16
        })

        expect(node.cpu_summary).to eq("1x Core i9-12900K")
      end
    end

    context "when node has no current_state" do
      it "returns nil" do
        node = create(:node)
        expect(node.cpu_summary).to be_nil
      end
    end

    context "when current_state has no cpu_info" do
      it "returns nil" do
        node = create(:node)
        create(:node_state, node: node, cpu_info: {})
        expect(node.cpu_summary).to be_nil
      end
    end

    context "when cpu_info has no model_name" do
      it "returns nil" do
        node = create(:node)
        create(:node_state, node: node, cpu_info: { "sockets" => 2, "cores" => 56 })
        expect(node.cpu_summary).to be_nil
      end
    end
  end

  describe "#ram_summary" do
    context "when node has current_state with mem_info" do
      it "returns formatted RAM summary in GB" do
        node = create(:node)
        create(:node_state, node: node, mem_info: {
          "total" => 2163427692544  # ~2015 GB
        })

        expect(node.ram_summary).to eq("2015 GB")
      end

      it "handles smaller memory amounts" do
        node = create(:node)
        create(:node_state, node: node, mem_info: {
          "total" => 68719476736  # 64 GB
        })

        expect(node.ram_summary).to eq("64 GB")
      end

      it "rounds to nearest GB" do
        node = create(:node)
        create(:node_state, node: node, mem_info: {
          "total" => 137438953472  # exactly 128 GB
        })

        expect(node.ram_summary).to eq("128 GB")
      end
    end

    context "when node has no current_state" do
      it "returns nil" do
        node = create(:node)
        expect(node.ram_summary).to be_nil
      end
    end

    context "when current_state has no mem_info" do
      it "returns nil" do
        node = create(:node)
        create(:node_state, node: node, mem_info: {})
        expect(node.ram_summary).to be_nil
      end
    end

    context "when mem_info has no total" do
      it "returns nil" do
        node = create(:node)
        create(:node_state, node: node, mem_info: { "free" => 1000000 })
        expect(node.ram_summary).to be_nil
      end
    end
  end

  describe "rack position validations" do
    let(:rack) { create(:equipment_rack, u_height: 42) }

    describe "#rack_position_within_bounds" do
      context "when rack and rack_position are present" do
        it "is valid when position is 1" do
          node = build(:node, rack: rack, rack_position: 1, rack_height: 1)
          expect(node).to be_valid
        end

        it "is valid when position + height - 1 equals rack u_height" do
          # Position 40, height 3 = occupies U40, U41, U42 (max = 42)
          node = build(:node, rack: rack, rack_position: 40, rack_height: 3)
          expect(node).to be_valid
        end

        it "is invalid when position is less than 1" do
          node = build(:node, rack: rack, rack_position: 0, rack_height: 1)
          expect(node).not_to be_valid
          expect(node.errors[:rack_position]).to include("must be at least 1")
        end

        it "is invalid when position + height - 1 exceeds rack u_height" do
          # Position 41, height 3 = occupies U41, U42, U43 (max = 43, exceeds 42)
          node = build(:node, rack: rack, rack_position: 41, rack_height: 3)
          expect(node).not_to be_valid
          expect(node.errors[:rack_position]).to include("exceeds rack height (max U42)")
        end

        it "is invalid when single-U node at position exceeds rack u_height" do
          node = build(:node, rack: rack, rack_position: 43, rack_height: 1)
          expect(node).not_to be_valid
          expect(node.errors[:rack_position]).to include("exceeds rack height (max U42)")
        end
      end

      context "when rack is nil" do
        it "skips validation" do
          node = build(:node, rack: nil, rack_position: 100, rack_height: 10)
          expect(node).to be_valid
        end
      end

      context "when rack_position is nil" do
        it "skips validation" do
          node = build(:node, rack: rack, rack_position: nil, rack_height: 10)
          expect(node).to be_valid
        end
      end
    end

    describe "#rack_position_no_overlap" do
      let!(:existing_node) do
        create(:node, rack: rack, rack_position: 10, rack_height: 3, rack_face: :front)
        # Occupies U10, U11, U12
      end

      context "same rack and face" do
        it "is invalid when new node overlaps from below" do
          # Position 9, height 2 = occupies U9, U10 (overlaps with U10)
          node = build(:node, rack: rack, rack_position: 9, rack_height: 2, rack_face: :front)
          expect(node).not_to be_valid
          expect(node.errors[:rack_position].first).to match(/overlaps with/)
        end

        it "is invalid when new node overlaps from above" do
          # Position 12, height 2 = occupies U12, U13 (overlaps with U12)
          node = build(:node, rack: rack, rack_position: 12, rack_height: 2, rack_face: :front)
          expect(node).not_to be_valid
          expect(node.errors[:rack_position].first).to match(/overlaps with/)
        end

        it "is invalid when new node is completely inside existing" do
          # Position 11, height 1 = occupies U11 (inside U10-U12)
          node = build(:node, rack: rack, rack_position: 11, rack_height: 1, rack_face: :front)
          expect(node).not_to be_valid
          expect(node.errors[:rack_position].first).to match(/overlaps with/)
        end

        it "is invalid when new node completely contains existing" do
          # Position 9, height 5 = occupies U9-U13 (contains U10-U12)
          node = build(:node, rack: rack, rack_position: 9, rack_height: 5, rack_face: :front)
          expect(node).not_to be_valid
          expect(node.errors[:rack_position].first).to match(/overlaps with/)
        end

        it "is valid when new node is directly adjacent below" do
          # Position 8, height 2 = occupies U8, U9 (no overlap with U10-U12)
          node = build(:node, rack: rack, rack_position: 8, rack_height: 2, rack_face: :front)
          expect(node).to be_valid
        end

        it "is valid when new node is directly adjacent above" do
          # Position 13, height 2 = occupies U13, U14 (no overlap with U10-U12)
          node = build(:node, rack: rack, rack_position: 13, rack_height: 2, rack_face: :front)
          expect(node).to be_valid
        end
      end

      context "same rack but different face" do
        it "is valid when nodes overlap on different faces" do
          # Same position as existing but rear face
          node = build(:node, rack: rack, rack_position: 10, rack_height: 3, rack_face: :rear)
          expect(node).to be_valid
        end
      end

      context "different racks" do
        let(:other_rack) { create(:equipment_rack, u_height: 42) }

        it "is valid when nodes have same position on different racks" do
          node = build(:node, rack: other_rack, rack_position: 10, rack_height: 3, rack_face: :front)
          expect(node).to be_valid
        end
      end

      context "updating existing node" do
        it "does not conflict with itself" do
          existing_node.rack_position = 11
          expect(existing_node).to be_valid
        end
      end
    end
  end
end
