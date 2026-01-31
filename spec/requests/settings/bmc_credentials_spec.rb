# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::BmcCredentials", type: :request do
  let(:user) { create(:user, :approver) }

  before { sign_in user }

  describe "GET /settings/bmc_credentials" do
    it "renders the BMC credentials settings page" do
      get settings_bmc_credentials_path
      expect(response).to have_http_status(:ok)
    end

    context "when global default exists" do
      let!(:credential) { create(:bmc_credential, :global_default) }

      it "shows existing credential" do
        get settings_bmc_credentials_path
        expect(response.body).to include(credential.bmc_address)
      end
    end
  end

  describe "PATCH /settings/bmc_credentials" do
    context "when no global default exists" do
      it "creates a global default credential" do
        patch settings_bmc_credentials_path, params: {
          bmc_credential: {
            bmc_address: "192.168.1.1",
            username: "admin",
            password: "secret",
            protocol: "auto"
          }
        }
        expect(response).to redirect_to(settings_bmc_credentials_path)
        expect(BmcCredential.global_default).to be_present
        expect(BmcCredential.global_default.bmc_address).to eq("192.168.1.1")
      end
    end

    context "when global default exists" do
      let!(:credential) { create(:bmc_credential, :global_default) }

      it "updates the existing credential" do
        patch settings_bmc_credentials_path, params: {
          bmc_credential: { username: "newadmin" }
        }
        expect(credential.reload.username).to eq("newadmin")
      end

      it "preserves password when blank" do
        original_password = credential.password
        patch settings_bmc_credentials_path, params: {
          bmc_credential: { username: "newadmin", password: "" }
        }
        expect(credential.reload.password).to eq(original_password)
      end
    end
  end
end
