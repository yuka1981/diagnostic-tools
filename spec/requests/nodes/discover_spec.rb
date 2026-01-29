# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes Discovery", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user) }

  describe "GET /nodes/discover" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns success" do
        salt_client = instance_double(SaltApiClient)
        allow(SaltApiClient).to receive(:new).and_return(salt_client)
        allow(salt_client).to receive(:get_minions).and_return({})

        get discover_nodes_path
        expect(response).to have_http_status(:ok)
      end

      it "assigns discovered minions" do
        salt_client = instance_double(SaltApiClient)
        allow(SaltApiClient).to receive(:new).and_return(salt_client)
        allow(salt_client).to receive(:get_minions).and_return({
          "new-node" => { "os" => "Rocky", "cpuarch" => "x86_64", "ipv4" => ["10.0.0.1"] }
        })

        get discover_nodes_path
        expect(response.body).to include("new-node")
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        get discover_nodes_path
        expect(response).to redirect_to(nodes_path)
      end
    end
  end

  describe "POST /nodes/import_minions" do
    before { sign_in approver }

    it "creates nodes from selected hostnames" do
      expect {
        post import_minions_nodes_path, params: { hostnames: ["import-node-01", "import-node-02"] }
      }.to change(Node, :count).by(2)
    end

    it "sets source to salt_discovery" do
      post import_minions_nodes_path, params: { hostnames: ["import-node-01"] }
      node = Node.find_by(hostname: "import-node-01")
      expect(node.source).to eq("salt_discovery")
    end

    it "sets salt_status to connected" do
      post import_minions_nodes_path, params: { hostnames: ["import-node-01"] }
      node = Node.find_by(hostname: "import-node-01")
      expect(node.salt_status).to eq("connected")
    end

    it "enqueues InventoryCollectJob for each imported node" do
      expect {
        post import_minions_nodes_path, params: { hostnames: ["import-node-01"] }
      }.to have_enqueued_job(InventoryCollectJob)
    end

    it "redirects with success notice" do
      post import_minions_nodes_path, params: { hostnames: ["import-node-01"] }
      expect(response).to redirect_to(nodes_path)
      follow_redirect!
      expect(response.body).to include("imported")
    end

    it "handles empty selection" do
      post import_minions_nodes_path, params: { hostnames: [] }
      expect(response).to redirect_to(nodes_path)
    end

    it "handles duplicate hostnames gracefully" do
      create(:node, hostname: "existing-node")
      post import_minions_nodes_path, params: { hostnames: ["existing-node"] }
      expect(response).to redirect_to(nodes_path)
    end
  end
end
