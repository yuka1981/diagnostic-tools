# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ApiKeys", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user, :viewer) }

  describe "GET /api_keys" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns http success" do
        get api_keys_path
        expect(response).to have_http_status(:success)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects to root" do
        get api_keys_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST /api_keys" do
    before { sign_in approver }

    it "creates a new api key" do
      expect {
        post api_keys_path, params: { api_key: { name: "New Cluster" } }
      }.to change(ApiKey, :count).by(1)
    end

    it "redirects to index with token in flash" do
      post api_keys_path, params: { api_key: { name: "New Cluster" } }
      expect(response).to redirect_to(api_keys_path)
      expect(flash[:notice]).to include("API Key was successfully created")
    end
  end

  describe "PATCH /api_keys/:id/revoke" do
    let!(:api_key) { create(:api_key) }
    before { sign_in approver }

    it "revokes the api key" do
      patch revoke_api_key_path(api_key)
      expect(api_key.reload.status).to eq("revoked")
    end
  end

  describe "DELETE /api_keys/:id" do
    let!(:active_key) { create(:api_key, status: :active) }
    let!(:revoked_key) { create(:api_key, status: :revoked) }

    context "when authenticated as approver" do
      before { sign_in approver }

      it "deletes a revoked api key" do
        expect {
          delete api_key_path(revoked_key)
        }.to change(ApiKey, :count).by(-1)
        expect(response).to redirect_to(api_keys_path)
        expect(flash[:notice]).to include("successfully deleted")
      end

      it "does not delete an active api key" do
        expect {
          delete api_key_path(active_key)
        }.not_to change(ApiKey, :count)
        expect(response).to redirect_to(api_keys_path)
        expect(flash[:alert]).to include("Only revoked API keys can be deleted")
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects to root" do
        delete api_key_path(revoked_key)
        expect(response).to redirect_to(root_path)
      end
    end
  end
end
