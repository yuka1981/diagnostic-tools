# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sites", type: :request do
  let(:user) { create(:user, :approver) }
  let(:site) { create(:site) }

  before do
    sign_in user
  end

  describe "GET /sites" do
    it "returns http success" do
      get sites_path
      expect(response).to have_http_status(:success)
    end

    it "displays sites" do
      site # create the site
      get sites_path
      expect(response.body).to include(site.name)
    end
  end

  describe "GET /sites/:id" do
    it "returns http success" do
      get site_path(site)
      expect(response).to have_http_status(:success)
    end

    it "shows site details" do
      get site_path(site)
      expect(response.body).to include(site.name)
    end

    context "with rooms" do
      let!(:room) { create(:room, site: site) }
      let!(:server_rack) { create(:server_rack, room: room) }

      it "displays rooms list" do
        get site_path(site)
        expect(response.body).to include(room.name)
      end

      it "shows rack count for the room" do
        get site_path(site)
        # Room has 1 rack
        expect(response.body).to include("Total Racks")
      end
    end
  end

  describe "GET /sites/new" do
    it "returns http success" do
      get new_site_path
      expect(response).to have_http_status(:success)
    end

    it "renders the form" do
      get new_site_path
      expect(response.body).to include("Name")
    end
  end

  describe "POST /sites" do
    let(:valid_params) do
      {
        site: {
          name: "Data Center A",
          description: "Primary data center"
        }
      }
    end

    it "creates a new site" do
      expect do
        post sites_path, params: valid_params
      end.to change(Site, :count).by(1)
    end

    it "redirects to sites index" do
      post sites_path, params: valid_params
      expect(response).to redirect_to(sites_path)
    end

    context "with invalid params" do
      let(:invalid_params) { { site: { name: "" } } }

      it "does not create a site" do
        expect do
          post sites_path, params: invalid_params
        end.not_to change(Site, :count)
      end

      it "renders unprocessable_entity status" do
        post sites_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /sites/:id/edit" do
    it "returns http success" do
      get edit_site_path(site)
      expect(response).to have_http_status(:success)
    end

    it "renders the form with existing data" do
      get edit_site_path(site)
      expect(response.body).to include(site.name)
    end
  end

  describe "PATCH /sites/:id" do
    let(:update_params) { { site: { description: "Updated description" } } }

    it "updates the site" do
      patch site_path(site), params: update_params
      expect(site.reload.description).to eq("Updated description")
    end

    it "redirects to sites index" do
      patch site_path(site), params: update_params
      expect(response).to redirect_to(sites_path)
    end

    context "with invalid params" do
      let(:invalid_params) { { site: { name: "" } } }

      it "renders edit with unprocessable_entity status" do
        patch site_path(site), params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /sites/:id" do
    it "deletes the site" do
      site_to_delete = create(:site)
      expect {
        delete site_path(site_to_delete)
      }.to change(Site, :count).by(-1)
    end

    it "redirects to sites index" do
      delete site_path(site)
      expect(response).to redirect_to(sites_path)
    end
  end

  describe "authorization" do
    let(:viewer_user) { create(:user, :viewer) }

    before do
      sign_in viewer_user
    end

    it "allows viewers to access index" do
      get sites_path
      expect(response).to have_http_status(:success)
    end

    it "allows viewers to access show" do
      get site_path(site)
      expect(response).to have_http_status(:success)
    end

    it "denies viewers access to new" do
      get new_site_path
      expect(response).to redirect_to(sites_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to create" do
      post sites_path, params: { site: { name: "Denied" } }
      expect(response).to redirect_to(sites_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to edit" do
      get edit_site_path(site)
      expect(response).to redirect_to(sites_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to update" do
      patch site_path(site), params: { site: { name: "Denied" } }
      expect(response).to redirect_to(sites_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to destroy" do
      delete site_path(site)
      expect(response).to redirect_to(sites_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "authentication" do
    before { sign_out user }

    it "requires authentication for index" do
      get sites_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "requires authentication for show" do
      get site_path(site)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
