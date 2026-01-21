# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ServerRacks", type: :request do
  let(:user) { create(:user, :approver) }
  let(:site) { create(:site) }
  let(:room) { create(:room, site: site) }
  let(:server_rack) { create(:server_rack, room: room) }

  before do
    sign_in user
  end

  describe "GET /racks" do
    it "returns http success" do
      get server_racks_path
      expect(response).to have_http_status(:success)
    end

    it "displays racks" do
      server_rack # create the rack
      get server_racks_path
      expect(response.body).to include(server_rack.name)
    end

    context "with site filter" do
      let(:other_site) { create(:site) }
      let(:other_room) { create(:room, site: other_site) }
      let!(:rack_in_site) { create(:server_rack, room: room, name: "FilteredRack") }
      let!(:rack_in_other_site) { create(:server_rack, room: other_room, name: "OtherRack") }

      it "filters racks by site when site_id param is provided" do
        get server_racks_path, params: { site_id: site.id }
        expect(response.body).to include("FilteredRack")
        expect(response.body).not_to include("OtherRack")
      end

      it "shows all racks when no site filter" do
        get server_racks_path
        expect(response.body).to include("FilteredRack")
        expect(response.body).to include("OtherRack")
      end
    end
  end

  describe "GET /racks/:id" do
    it "returns http success" do
      get server_rack_path(server_rack)
      expect(response).to have_http_status(:success)
    end

    it "shows rack details" do
      get server_rack_path(server_rack)
      expect(response.body).to include(server_rack.name)
      expect(response.body).to include(server_rack.site.name)
    end

    context "with mounted nodes" do
      let!(:node) { create(:node, server_rack: server_rack, rack_position: 10, rack_height: 2) }

      it "displays mounted nodes" do
        get server_rack_path(server_rack)
        expect(response.body).to include(node.hostname)
      end
    end
  end

  describe "GET /racks/new" do
    it "returns http success" do
      get new_server_rack_path
      expect(response).to have_http_status(:success)
    end

    it "renders the form" do
      get new_server_rack_path
      expect(response.body).to include("Name")
      expect(response.body).to include("U Height")
    end

    it "preselects room when room_id param is provided" do
      get new_server_rack_path, params: { room_id: room.id }
      expect(response).to have_http_status(:success)
      # The room should be preselected in the form
      expect(response.body).to include(room.name)
    end
  end

  describe "POST /racks" do
    let(:valid_params) do
      {
        server_rack: {
          room_id: room.id,
          name: "New Rack A1",
          u_height: 42,
          status: "active",
          facility_id: "FAC-001",
          asset_tag: "ASSET-001",
          desc_units: false
        }
      }
    end

    it "creates a new rack" do
      expect do
        post server_racks_path, params: valid_params
      end.to change(ServerRack, :count).by(1)
    end

    it "redirects to racks index" do
      post server_racks_path, params: valid_params
      expect(response).to redirect_to(server_racks_path)
    end

    context "with invalid params" do
      let(:invalid_params) { { server_rack: { name: "", room_id: room.id, u_height: 42 } } }

      it "does not create a rack" do
        expect do
          post server_racks_path, params: invalid_params
        end.not_to change(ServerRack, :count)
      end

      it "renders unprocessable_entity status" do
        post server_racks_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /racks/:id/edit" do
    it "returns http success" do
      get edit_server_rack_path(server_rack)
      expect(response).to have_http_status(:success)
    end

    it "renders the form with existing data" do
      get edit_server_rack_path(server_rack)
      expect(response.body).to include(server_rack.name)
    end
  end

  describe "PATCH /racks/:id" do
    let(:update_params) { { server_rack: { facility_id: "UPDATED-FAC" } } }

    it "updates the rack" do
      patch server_rack_path(server_rack), params: update_params
      expect(server_rack.reload.facility_id).to eq("UPDATED-FAC")
    end

    it "redirects to racks index" do
      patch server_rack_path(server_rack), params: update_params
      expect(response).to redirect_to(server_racks_path)
    end

    context "with invalid params" do
      let(:invalid_params) { { server_rack: { name: "" } } }

      it "renders edit with unprocessable_entity status" do
        patch server_rack_path(server_rack), params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /racks/:id" do
    it "deletes the rack" do
      rack_to_delete = create(:server_rack)
      expect {
        delete server_rack_path(rack_to_delete)
      }.to change(ServerRack, :count).by(-1)
    end

    it "redirects to racks index" do
      delete server_rack_path(server_rack)
      expect(response).to redirect_to(server_racks_path)
    end
  end

  describe "PATCH /racks/:id/update_layout" do
    let(:node) { create(:node, server_rack: server_rack, rack_position: 1, rack_height: 2) }
    let(:layout_params) do
      {
        layout: [
          { node_id: node.id, rack_position: 10 }
        ]
      }
    end

    it "returns http success" do
      patch update_layout_server_rack_path(server_rack), params: layout_params, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe "authorization" do
    let(:viewer_user) { create(:user, :viewer) }

    before do
      sign_in viewer_user
    end

    it "allows viewers to access index" do
      get server_racks_path
      expect(response).to have_http_status(:success)
    end

    it "allows viewers to access show" do
      get server_rack_path(server_rack)
      expect(response).to have_http_status(:success)
    end

    it "denies viewers access to new" do
      get new_server_rack_path
      expect(response).to redirect_to(server_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to create" do
      post server_racks_path, params: { server_rack: { name: "Denied", room_id: room.id, u_height: 42 } }
      expect(response).to redirect_to(server_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to edit" do
      get edit_server_rack_path(server_rack)
      expect(response).to redirect_to(server_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to update" do
      patch server_rack_path(server_rack), params: { server_rack: { name: "Denied" } }
      expect(response).to redirect_to(server_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to destroy" do
      delete server_rack_path(server_rack)
      expect(response).to redirect_to(server_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to update_layout" do
      patch update_layout_server_rack_path(server_rack), params: { layout: [] }, as: :json
      expect(response).to redirect_to(server_racks_path)
    end
  end

  describe "authentication" do
    before { sign_out user }

    it "requires authentication for index" do
      get server_racks_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "requires authentication for show" do
      get server_rack_path(server_rack)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
