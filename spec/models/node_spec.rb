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
end
