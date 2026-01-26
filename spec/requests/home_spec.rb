# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home", type: :request do
  describe "GET /" do
    context "when not authenticated" do
      it "redirects to sign in page" do
        get root_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      let(:user) { create(:user) }

      before { sign_in user }

      it "returns http success" do
        get root_path
        expect(response).to have_http_status(:success)
      end

      it "displays the dashboard" do
        get root_path
        expect(response.body).to include("Dashboard")
        expect(response.body).to include("QCT InfraScope")
      end
    end
  end
end
