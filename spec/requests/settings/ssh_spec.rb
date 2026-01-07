# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::Ssh", type: :request do
  let(:user) { create(:user, :approver) }

  before do
    sign_in user
  end

  describe "GET /settings/ssh" do
    it "returns http success" do
      get settings_ssh_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /settings/ssh" do
    let(:params) do
      {
        ssh_setting: {
          bastion_host: "1.2.3.4",
          bastion_user: "admin",
          bastion_port: 2222
        }
      }
    end

    it "updates the settings" do
      patch settings_ssh_path, params: params
      expect(response).to redirect_to(settings_ssh_path)

      setting = SshSetting.current
      expect(setting.bastion_host).to eq("1.2.3.4")
      expect(setting.bastion_user).to eq("admin")
      expect(setting.bastion_port).to eq(2222)
    end
  end

  context "as a viewer" do
    let(:viewer) { create(:user, role: :viewer) }

    before do
      sign_in viewer
    end

    it "redirects to root" do
      get settings_ssh_path
      expect(response).to redirect_to(root_path)
    end
  end
end
