# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rooms", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user, :viewer) }

  describe "GET /rooms" do
    let!(:room) { create(:room) }

    context "when authenticated" do
      before { sign_in viewer }

      it "returns http success" do
        get rooms_path
        expect(response).to have_http_status(:success)
      end

      it "displays the rooms" do
        get rooms_path
        expect(response.body).to include(room.name)
      end
    end

    context "when not authenticated" do
      it "redirects to login" do
        get rooms_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /rooms/:id" do
    let!(:room) { create(:room) }

    context "when authenticated" do
      before { sign_in viewer }

      it "returns http success" do
        get room_path(room)
        expect(response).to have_http_status(:success)
      end

      it "displays the room details" do
        get room_path(room)
        expect(response.body).to include(room.name)
      end
    end
  end

  describe "GET /rooms/new" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns http success" do
        get new_room_path
        expect(response).to have_http_status(:success)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        get new_room_path
        expect(response).to redirect_to(rooms_path)
      end
    end
  end

  describe "POST /rooms" do
    let(:valid_params) do
      {
        room: {
          name: "Machine Room A",
          description: "Primary data center room"
        }
      }
    end

    let(:invalid_params) do
      {
        room: {
          name: "",
          description: "Missing name"
        }
      }
    end

    context "when authenticated as approver" do
      before { sign_in approver }

      it "creates a new room with valid params" do
        expect {
          post rooms_path, params: valid_params
        }.to change(Room, :count).by(1)
      end

      it "redirects to the room after creation" do
        post rooms_path, params: valid_params
        expect(response).to redirect_to(room_path(Room.last))
      end

      it "does not create with invalid params" do
        expect {
          post rooms_path, params: invalid_params
        }.not_to change(Room, :count)
      end

      it "renders new on validation error" do
        post rooms_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        post rooms_path, params: valid_params
        expect(response).to redirect_to(rooms_path)
      end
    end
  end

  describe "GET /rooms/:id/edit" do
    let!(:room) { create(:room) }

    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns http success" do
        get edit_room_path(room)
        expect(response).to have_http_status(:success)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        get edit_room_path(room)
        expect(response).to redirect_to(rooms_path)
      end
    end
  end

  describe "PATCH /rooms/:id" do
    let!(:room) { create(:room) }

    context "when authenticated as approver" do
      before { sign_in approver }

      it "updates the room" do
        patch room_path(room), params: {
          room: { description: "Updated description" }
        }
        expect(room.reload.description).to eq("Updated description")
      end

      it "redirects to the room" do
        patch room_path(room), params: {
          room: { description: "Updated" }
        }
        expect(response).to redirect_to(room_path(room))
      end

      it "renders edit on validation error" do
        patch room_path(room), params: {
          room: { name: "" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        patch room_path(room), params: {
          room: { description: "Hacked" }
        }
        expect(response).to redirect_to(rooms_path)
      end
    end
  end

  describe "DELETE /rooms/:id" do
    let!(:room) { create(:room) }

    context "when authenticated as approver" do
      before { sign_in approver }

      context "when room has no racks" do
        it "deletes the room" do
          expect {
            delete room_path(room)
          }.to change(Room, :count).by(-1)
        end

        it "redirects to index" do
          delete room_path(room)
          expect(response).to redirect_to(rooms_path)
        end
      end

      context "when room has associated racks" do
        let!(:rack) { create(:equipment_rack, room: room) }

        it "does not delete the room" do
          expect {
            delete room_path(room)
          }.not_to change(Room, :count)
        end

        it "shows error message" do
          delete room_path(room)
          expect(flash[:alert]).to be_present
        end
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        delete room_path(room)
        expect(response).to redirect_to(rooms_path)
      end
    end
  end
end
