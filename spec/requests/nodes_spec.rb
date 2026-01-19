# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes", type: :request do
  let(:user) { create(:user, :approver) }
  let(:node) { create(:node) }

  before do
    sign_in user
  end

  describe "GET /nodes" do
    it "returns http success" do
      get nodes_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /nodes/:id" do
    it "returns http success" do
      get node_path(node)
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /nodes/new" do
    it "returns http success" do
      get new_node_path
      expect(response).to have_http_status(:success)
    end

    it "renders within turbo frame" do
      get new_node_path
      expect(response.body).to include('turbo-frame id="node_modal"')
    end
  end

  describe "POST /nodes" do
    let(:valid_params) do
      {
        node: {
          hostname: "new-node",
          role: "compute",
          arch: "x86_64",
          ssh_port: 22,
          ssh_user: "root",
          ssh_key: "ssh-rsa ...",
          password: "password123"
        }
      }
    end

    it "creates a new node" do
      expect do
        post nodes_path, params: valid_params
      end.to change(Node, :count).by(1)
    end

    it "redirects to nodes index" do
      post nodes_path, params: valid_params
      expect(response).to redirect_to(nodes_path)
    end

    it "returns turbo stream when requested" do
      post nodes_path, params: valid_params, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream action=\"append\" target=\"nodes_tbody\"")
    end
  end

  describe "GET /nodes/:id/edit" do
    it "returns http success" do
      get edit_node_path(node)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /nodes/:id" do
    let(:update_params) { { node: { ssh_port: 2222 } } }

    it "updates the node" do
      patch node_path(node), params: update_params
      expect(node.reload.ssh_port).to eq(2222)
    end

    it "returns turbo stream when requested" do
      patch node_path(node), params: update_params, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream action=\"replace\"")
    end

    it "includes flash message update in turbo stream response" do
      patch node_path(node), params: update_params, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include("flash_messages")
    end

    it "replaces node_modal with empty frame in turbo stream response" do
      patch node_path(node), params: update_params, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("node_modal")
    end

    it "can update ssh_password field" do
      patch node_path(node), params: { node: { ssh_password: "new_ssh_pass" } }
      expect(node.reload.ssh_password).to eq("new_ssh_pass")
    end

    it "keeps ssh_password separate from sudo_credential" do
      patch node_path(node), params: { node: { ssh_password: "ssh_pass", sudo_credential: "sudo_pass" } }
      node.reload
      expect(node.ssh_password).to eq("ssh_pass")
      expect(node.sudo_credential).to eq("sudo_pass")
    end

    context "with invalid params" do
      it "renders edit form with unprocessable_entity status" do
        # Assuming hostname is required - adjust if needed
        patch node_path(node), params: { node: { hostname: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /nodes/:id" do
    it "deletes the node" do
      node_to_delete = create(:node)
      expect {
        delete node_path(node_to_delete)
      }.to change(Node, :count).by(-1)
    end

    it "returns turbo stream when requested" do
      delete node_path(node), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream action=\"remove\"")
    end
  end

  describe "POST /nodes/:id/test_connection" do
    let(:service_double) { instance_double(Inventory::TriggerCollectService) }

    before do
      allow(Inventory::TriggerCollectService).to receive(:new).with(any_args).and_return(service_double)
    end

    it "returns success message when connection succeeds" do
      allow(service_double).to receive(:call).and_return(double(success?: true))
      post test_connection_node_path(node), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Connection to #{node.hostname} successful!")
    end

    it "returns error message when connection fails" do
      allow(service_double).to receive(:call).and_return(double(success?: false, error: "Authentication failed"))
      post test_connection_node_path(node), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Connection to #{node.hostname} failed")
    end
  end

  describe "POST /nodes/:id/collect" do
    let(:trigger_double) { instance_double(Inventory::TriggerCollectService) }
    let(:process_double) { instance_double(Inventory::ProcessStateService) }

    before do
      allow(Inventory::TriggerCollectService).to receive(:new).with(node).and_return(trigger_double)
    end

    it "returns success message and updates data when collection succeeds" do
      allow(trigger_double).to receive(:call).and_return(double(success?: true, output: { host: { hostname: node.hostname } }))
      allow(Inventory::ProcessStateService).to receive(:new).and_return(process_double)
      allow(process_double).to receive(:call).and_return(double(success?: true, state_created: true, node_state: build(:node_state)))

      post collect_node_path(node), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("System information collected successfully")
    end

    it "returns error message when collection fails" do
      allow(trigger_double).to receive(:call).and_return(double(success?: false, error: "Agent not found"))
      post collect_node_path(node), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Agent not found")
    end
  end

  describe "authorization" do
    let(:regular_user) { create(:user, :viewer) }

    before do
      sign_in regular_user
    end

    it "denies access to new node" do
      get new_node_path
      expect(response).to redirect_to(nodes_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to create node" do
      post nodes_path, params: { node: { hostname: "denied" } }
      expect(response).to redirect_to(nodes_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to edit node" do
      get edit_node_path(node)
      expect(response).to redirect_to(nodes_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to update node" do
      patch node_path(node), params: { node: { hostname: "denied" } }
      expect(response).to redirect_to(nodes_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to delete node" do
      delete node_path(node)
      expect(response).to redirect_to(nodes_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to test connection" do
      post test_connection_node_path(node)
      expect(response).to redirect_to(nodes_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to collect" do
      post collect_node_path(node)
      expect(response).to redirect_to(nodes_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "authentication" do
    before { sign_out user }

    it "requires authentication for index" do
      get nodes_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "rack assignment" do
    let(:room) { create(:room, name: "Server Room A") }
    let(:rack) { create(:equipment_rack, name: "Rack-01", room: room, u_height: 42) }

    describe "GET /nodes/new" do
      it "renders Physical Location section" do
        get new_node_path
        expect(response.body).to include("Physical Location")
        expect(response.body).to include("Rack")
        expect(response.body).to include("Position (U)")
        expect(response.body).to include("Height (U)")
        expect(response.body).to include("Face")
      end

      it "includes available racks in dropdown" do
        rack # create the rack
        get new_node_path
        expect(response.body).to include("Server Room A - Rack-01")
      end
    end

    describe "POST /nodes with rack fields" do
      let(:valid_params_with_rack) do
        {
          node: {
            hostname: "racked-node",
            role: "compute",
            arch: "x86_64",
            ssh_port: 22,
            rack_id: rack.id,
            rack_position: 10,
            rack_height: 2,
            rack_face: "front"
          }
        }
      end

      it "creates a node with rack assignment" do
        expect do
          post nodes_path, params: valid_params_with_rack
        end.to change(Node, :count).by(1)

        created_node = Node.last
        expect(created_node.rack).to eq(rack)
        expect(created_node.rack_position).to eq(10)
        expect(created_node.rack_height).to eq(2)
        expect(created_node.rack_face).to eq("front")
      end
    end

    describe "PATCH /nodes/:id with rack fields" do
      it "can assign a node to a rack" do
        patch node_path(node), params: {
          node: {
            rack_id: rack.id,
            rack_position: 5,
            rack_height: 1,
            rack_face: "rear"
          }
        }

        node.reload
        expect(node.rack).to eq(rack)
        expect(node.rack_position).to eq(5)
        expect(node.rack_height).to eq(1)
        expect(node.rack_face).to eq("rear")
      end

      it "can remove rack assignment" do
        node.update!(rack: rack, rack_position: 1, rack_height: 1)

        patch node_path(node), params: { node: { rack_id: "" } }

        node.reload
        expect(node.rack).to be_nil
      end
    end

    describe "GET /nodes/:id/edit" do
      it "renders Physical Location section" do
        get edit_node_path(node)
        expect(response.body).to include("Physical Location")
      end

      it "includes available racks in dropdown" do
        rack # create the rack
        get edit_node_path(node)
        expect(response.body).to include("Server Room A - Rack-01")
      end
    end
  end
end
