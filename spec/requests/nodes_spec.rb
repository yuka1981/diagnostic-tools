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
          ssh_user: "root"
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
  end

  describe "DELETE /nodes/:id" do
    it "deletes the node" do
      node_to_delete = create(:node)
      expect do
        delete node_path(node_to_delete)
      end.to change(Node, :count).by(-1)
    end

    it "returns turbo stream when requested" do
      delete node_path(node), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream action=\"remove\"")
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
  end

  describe "authentication" do
    before { sign_out user }

    it "requires authentication for index" do
      get nodes_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
