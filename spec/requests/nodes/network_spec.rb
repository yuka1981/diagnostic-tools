# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Networks", type: :request do
  let(:user) { create(:user, :approver) }
  let(:node) { create(:node) }
  let(:node_state) { create(:node_state, node: node, network_inventory: { "interfaces" => [ { "name" => "ib0", "type" => "infiniband", "infiniband" => { "lid" => "14" } } ] }) }

  before do
    sign_in user
  end

  describe "GET /nodes/:node_id/network/ib_details" do
    it "returns http success" do
      get ib_details_node_network_path(node_id: node.id, interface_name: "ib0", state_id: node_state.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("ib0")
      expect(response.body).to include("14")
    end

    it "renders placeholder when interface not found" do
      get ib_details_node_network_path(node_id: node.id, interface_name: "nonexistent", state_id: node_state.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Interface information not found")
    end
  end
end
