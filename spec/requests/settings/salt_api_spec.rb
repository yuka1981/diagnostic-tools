# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::SaltApi", type: :request do
  let(:user) { create(:user, :approver) }

  before do
    sign_in user
  end

  describe "GET /settings/salt_api" do
    it "returns http success" do
      get settings_salt_api_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /settings/salt_api" do
    let(:params) do
      {
        salt_setting: {
          base_url: "http://salt-master:8000",
          username: "saltadmin",
          password: "secret",
          ca_cert_path: "/etc/ssl/salt-ca.pem",
          verify_ssl: false
        }
      }
    end

    it "updates the settings" do
      patch settings_salt_api_path, params: params
      expect(response).to redirect_to(settings_salt_api_path)

      setting = SaltSetting.current
      expect(setting.base_url).to eq("http://salt-master:8000")
      expect(setting.username).to eq("saltadmin")
      expect(setting.verify_ssl).to be false
    end

    it "preserves password when not submitted" do
      SaltSetting.create!(base_url: "http://salt:8000", username: "admin", password: "original")
      patch settings_salt_api_path, params: { salt_setting: { base_url: "http://salt:9000", password: "" } }
      expect(SaltSetting.current.password).to eq("original")
    end

    it "clears password when clear flag is set" do
      SaltSetting.create!(base_url: "http://salt:8000", username: "admin", password: "original")
      patch settings_salt_api_path, params: { salt_setting: { clear_password: "1" } }
      expect(SaltSetting.current.password).to be_nil
    end

    it "renders show with errors for invalid base_url" do
      patch settings_salt_api_path, params: { salt_setting: { base_url: "ftp://invalid" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /settings/salt_api/test_connection" do
    it "returns success when Salt API is reachable" do
      SaltSetting.create!(base_url: "http://salt:8000", username: "admin", password: "secret")

      stub_request(:post, "http://salt:8000/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "t", expire: (Time.current + 1.hour).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      stub_request(:get, "http://salt:8000/minions")
        .to_return(
          status: 200,
          body: { return: [ { "node-01" => {}, "node-02" => {} } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      post test_connection_settings_salt_api_path, as: :turbo_stream
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Connected")
      expect(response.body).to include("2 minions")
    end

    it "returns failure when Salt API is unreachable" do
      SaltSetting.create!(base_url: "http://salt:8000", username: "admin", password: "bad")

      stub_request(:post, "http://salt:8000/login")
        .to_return(status: 401, body: "Unauthorized")

      post test_connection_settings_salt_api_path, as: :turbo_stream
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Failed")
    end

    it "returns not configured when settings are blank" do
      post test_connection_settings_salt_api_path, as: :turbo_stream
      expect(response).to have_http_status(:success)
      expect(response.body).to include("not configured")
    end
  end

  context "as a viewer" do
    let(:viewer) { create(:user, role: :viewer) }

    before { sign_in viewer }

    it "redirects to root" do
      get settings_salt_api_path
      expect(response).to redirect_to(root_path)
    end
  end
end
