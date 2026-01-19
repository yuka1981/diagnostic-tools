# frozen_string_literal: true

require "rails_helper"

RSpec.describe "EquipmentRacks", type: :request do
  let(:user) { create(:user, :approver) }
  let(:room) { create(:room) }
  let(:equipment_rack) { create(:equipment_rack, room: room) }

  before do
    sign_in user
  end

  describe "GET /racks" do
    it "returns http success" do
      get equipment_racks_path
      expect(response).to have_http_status(:success)
    end

    it "lists all racks with room name" do
      rack_with_room = create(:equipment_rack, name: "R01", room: room)
      rack_without_room = create(:equipment_rack, name: "R02", room: nil)

      get equipment_racks_path

      expect(response.body).to include("R01")
      expect(response.body).to include(room.name)
      expect(response.body).to include("R02")
      expect(response.body).to include("Unassigned")
    end

    it "shows utilization percentage" do
      rack = create(:equipment_rack, u_height: 42)
      get equipment_racks_path

      expect(response.body).to include("0.0%")
    end
  end

  describe "GET /racks/:id" do
    it "returns http success" do
      get equipment_rack_path(equipment_rack)
      expect(response).to have_http_status(:success)
    end

    it "shows rack details" do
      get equipment_rack_path(equipment_rack)

      expect(response.body).to include(equipment_rack.name)
      expect(response.body).to include(equipment_rack.u_height.to_s)
    end

    it "shows associated nodes" do
      node = create(:node, rack: equipment_rack, rack_position: 1, rack_height: 2)
      get equipment_rack_path(equipment_rack)

      expect(response.body).to include(node.hostname)
    end

    it "shows room name or Unassigned" do
      get equipment_rack_path(equipment_rack)
      expect(response.body).to include(room.name)

      rack_no_room = create(:equipment_rack, room: nil)
      get equipment_rack_path(rack_no_room)
      expect(response.body).to include("Unassigned")
    end
  end

  describe "GET /racks/new" do
    it "returns http success" do
      get new_equipment_rack_path
      expect(response).to have_http_status(:success)
    end

    it "renders form with room select" do
      room # ensure room exists
      get new_equipment_rack_path
      expect(response.body).to include("select")
      expect(response.body).to include(room.name)
    end

    it "renders within turbo frame" do
      get new_equipment_rack_path
      expect(response.body).to include('turbo-frame id="equipment_rack_modal"')
    end
  end

  describe "POST /racks" do
    let(:valid_params) do
      {
        equipment_rack: {
          name: "New-Rack-01",
          u_height: 42,
          width: 19,
          room_id: room.id,
          notes: "Test notes"
        }
      }
    end

    it "creates a new equipment rack" do
      expect do
        post equipment_racks_path, params: valid_params
      end.to change(EquipmentRack, :count).by(1)
    end

    it "redirects to racks index" do
      post equipment_racks_path, params: valid_params
      expect(response).to redirect_to(equipment_racks_path)
    end

    it "returns turbo stream when requested" do
      post equipment_racks_path, params: valid_params, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream action=\"append\" target=\"equipment_racks_tbody\"")
    end

    context "with invalid params" do
      it "renders new form with unprocessable_entity status" do
        post equipment_racks_path, params: { equipment_rack: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /racks/:id/edit" do
    it "returns http success" do
      get edit_equipment_rack_path(equipment_rack)
      expect(response).to have_http_status(:success)
    end

    it "renders within turbo frame" do
      get edit_equipment_rack_path(equipment_rack)
      expect(response.body).to include('turbo-frame id="equipment_rack_modal"')
    end
  end

  describe "PATCH /racks/:id" do
    let(:update_params) { { equipment_rack: { name: "Updated-Rack-Name" } } }

    it "updates the equipment rack" do
      patch equipment_rack_path(equipment_rack), params: update_params
      expect(equipment_rack.reload.name).to eq("Updated-Rack-Name")
    end

    it "redirects to racks index" do
      patch equipment_rack_path(equipment_rack), params: update_params
      expect(response).to redirect_to(equipment_racks_path)
    end

    it "returns turbo stream when requested" do
      patch equipment_rack_path(equipment_rack), params: update_params, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream action=\"replace\"")
    end

    context "with u_height constraint violation" do
      it "prevents reducing u_height below occupied position" do
        node = create(:node, rack: equipment_rack, rack_position: 40, rack_height: 2)
        # Node occupies positions 40-41, so u_height cannot be reduced below 41
        patch equipment_rack_path(equipment_rack), params: { equipment_rack: { u_height: 30 } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(equipment_rack.reload.u_height).to eq(42) # unchanged
      end
    end

    context "with invalid params" do
      it "renders edit form with unprocessable_entity status" do
        patch equipment_rack_path(equipment_rack), params: { equipment_rack: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /racks/:id" do
    it "deletes the equipment rack" do
      rack_to_delete = create(:equipment_rack)
      expect {
        delete equipment_rack_path(rack_to_delete)
      }.to change(EquipmentRack, :count).by(-1)
    end

    it "redirects to racks index" do
      delete equipment_rack_path(equipment_rack)
      expect(response).to redirect_to(equipment_racks_path)
    end

    it "sets rack_id to nil on associated nodes (nullify)" do
      node = create(:node, rack: equipment_rack, rack_position: 1, rack_height: 2)
      delete equipment_rack_path(equipment_rack)
      expect(node.reload.rack_id).to be_nil
    end

    it "returns turbo stream when requested" do
      delete equipment_rack_path(equipment_rack), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream action=\"remove\"")
    end
  end

  describe "authorization" do
    let(:regular_user) { create(:user, :viewer) }

    before do
      sign_in regular_user
    end

    it "denies access to new rack" do
      get new_equipment_rack_path
      expect(response).to redirect_to(equipment_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to create rack" do
      post equipment_racks_path, params: { equipment_rack: { name: "denied" } }
      expect(response).to redirect_to(equipment_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to edit rack" do
      get edit_equipment_rack_path(equipment_rack)
      expect(response).to redirect_to(equipment_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to update rack" do
      patch equipment_rack_path(equipment_rack), params: { equipment_rack: { name: "denied" } }
      expect(response).to redirect_to(equipment_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "denies access to delete rack" do
      delete equipment_rack_path(equipment_rack)
      expect(response).to redirect_to(equipment_racks_path)
      expect(flash[:alert]).to be_present
    end

    it "allows read access to index" do
      get equipment_racks_path
      expect(response).to have_http_status(:success)
    end

    it "allows read access to show" do
      get equipment_rack_path(equipment_rack)
      expect(response).to have_http_status(:success)
    end
  end

  describe "authentication" do
    before { sign_out user }

    it "requires authentication for index" do
      get equipment_racks_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
