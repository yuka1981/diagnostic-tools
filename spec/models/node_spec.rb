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
    it "returns true if last_seen_at is within 5 minutes" do
      node = build(:node, last_seen_at: 2.minutes.ago)
      expect(node).to be_online
    end

    it "returns false if last_seen_at is older than 5 minutes" do
      node = build(:node, last_seen_at: 10.minutes.ago)
      expect(node).not_to be_online
    end

    it "returns false if last_seen_at is nil" do
      node = build(:node, last_seen_at: nil)
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
end
