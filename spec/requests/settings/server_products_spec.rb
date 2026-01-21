# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::ServerProducts", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user) }

  describe "GET /settings/server_products" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns success" do
        get settings_server_products_path
        expect(response).to have_http_status(:success)
      end

      it "displays server products" do
        product = create(:server_product, name: "QuantaGrid D54Q-2U")
        get settings_server_products_path
        expect(response.body).to include("QuantaGrid D54Q-2U")
      end

      it "displays last sync information" do
        create(:sync_log, source: "qct", completed_at: 1.day.ago)
        get settings_server_products_path
        expect(response.body).to include("Last synced")
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects to root" do
        get settings_server_products_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "when not authenticated" do
      it "redirects to sign in" do
        get settings_server_products_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
