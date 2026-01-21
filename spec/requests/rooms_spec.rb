# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rooms", type: :request do
  let(:user) { create(:user, :approver) }
  let(:site) { create(:site) }
  let(:room) { create(:room, site: site) }

  before do
    sign_in user
  end

  describe "GET /rooms" do
    it "returns http success" do
      get rooms_path
      expect(response).to have_http_status(:success)
    end

    it "displays rooms" do
      room # create the room
      get rooms_path
      expect(response.body).to include(room.name)
    end

    context "with site filter" do
      let(:other_site) { create(:site) }
      let!(:room_in_site) { create(:room, site: site, name: "FilteredRoom") }
      let!(:room_in_other_site) { create(:room, site: other_site, name: "OtherRoom") }

      it "filters rooms by site when site_id param is provided" do
        get rooms_path, params: { site_id: site.id }
        expect(response.body).to include("FilteredRoom")
        expect(response.body).not_to include("OtherRoom")
      end

      it "shows all rooms when no site filter" do
        get rooms_path
        expect(response.body).to include("FilteredRoom")
        expect(response.body).to include("OtherRoom")
      end
    end
  end

  describe "GET /rooms/:id" do
    it "returns http success" do
      get room_path(room)
      expect(response).to have_http_status(:success)
    end

    it "shows room details" do
      get room_path(room)
      expect(response.body).to include(room.name)
      expect(response.body).to include(room.site.name)
    end

    context "with racks" do
      let!(:server_rack) { create(:server_rack, room: room) }

      it "displays racks" do
        get room_path(room)
        expect(response.body).to include(server_rack.name)
      end
    end
  end

  describe "GET /rooms/new" do
    it "returns http success" do
      get new_room_path
      expect(response).to have_http_status(:success)
    end

    it "renders the form" do
      get new_room_path
      expect(response.body).to include("Name")
      expect(response.body).to include("Site")
    end

    it "preselects site when site_id param is provided" do
      get new_room_path, params: { site_id: site.id }
      expect(response).to have_http_status(:success)
      # The site should be preselected in the form
      expect(response.body).to include(site.name)
    end
  end

  describe "POST /rooms" do
    let(:valid_params) do
      {
        room: {
          site_id: site.id,
          name: "New Server Room",
          description: "A new server room"
        }
      }
    end

    it "creates a new room" do
      expect do
        post rooms_path, params: valid_params
      end.to change(Room, :count).by(1)
    end

    it "redirects to room show page" do
      post rooms_path, params: valid_params
      expect(response).to redirect_to(room_path(Room.last))
    end

    context "with invalid params" do
      let(:invalid_params) { { room: { name: "", site_id: site.id } } }

      it "does not create a room" do
        expect do
          post rooms_path, params: invalid_params
        end.not_to change(Room, :count)
      end

      it "renders unprocessable_entity status" do
        post rooms_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /rooms/:id/edit" do
    it "returns http success" do
      get edit_room_path(room)
      expect(response).to have_http_status(:success)
    end

    it "renders the form with existing data" do
      get edit_room_path(room)
      expect(response.body).to include(room.name)
    end
  end

  describe "PATCH /rooms/:id" do
    let(:update_params) { { room: { description: "Updated description" } } }

    it "updates the room" do
      patch room_path(room), params: update_params
      expect(room.reload.description).to eq("Updated description")
    end

    it "redirects to room show page" do
      patch room_path(room), params: update_params
      expect(response).to redirect_to(room_path(room))
    end

    context "with invalid params" do
      let(:invalid_params) { { room: { name: "" } } }

      it "renders edit with unprocessable_entity status" do
        patch room_path(room), params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /rooms/:id" do
    context "when room has no racks" do
      it "deletes the room" do
        room_to_delete = create(:room)
        expect {
          delete room_path(room_to_delete)
        }.to change(Room, :count).by(-1)
      end

      it "redirects to rooms index" do
        room_to_delete = create(:room)
        delete room_path(room_to_delete)
        expect(response).to redirect_to(rooms_path)
      end
    end

    context "when room has racks" do
      let!(:server_rack) { create(:server_rack, room: room) }

      it "does not delete the room" do
        expect {
          delete room_path(room)
        }.not_to change(Room, :count)
      end

      it "redirects to room show page with alert" do
        delete room_path(room)
        expect(response).to redirect_to(room_path(room))
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "GET /rooms/for_site" do
    let!(:room_in_site) { create(:room, site: site, name: "Room A") }
    let!(:other_site) { create(:site) }
    let!(:room_in_other_site) { create(:room, site: other_site, name: "Room B") }

    it "returns rooms for specified site as JSON" do
      get for_site_rooms_path, params: { site_id: site.id }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")

      json_response = JSON.parse(response.body)
      room_names = json_response.map { |r| r["name"] }
      expect(room_names).to include("Room A")
      expect(room_names).not_to include("Room B")
    end
  end

  describe "authorization" do
    let(:viewer_user) { create(:user, :viewer) }

    before do
      sign_in viewer_user
    end

    it "allows viewers to access index" do
      get rooms_path
      expect(response).to have_http_status(:success)
    end

    it "allows viewers to access show" do
      get room_path(room)
      expect(response).to have_http_status(:success)
    end

    it "denies viewers access to new" do
      get new_room_path
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to create" do
      post rooms_path, params: { room: { name: "Denied", site_id: site.id } }
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to edit" do
      get edit_room_path(room)
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to update" do
      patch room_path(room), params: { room: { name: "Denied" } }
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to destroy" do
      delete room_path(room)
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "authentication" do
    before { sign_out user }

    it "requires authentication for index" do
      get rooms_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "requires authentication for show" do
      get room_path(room)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
