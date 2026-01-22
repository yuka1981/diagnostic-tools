# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::SshProfiles", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user) }

  describe "GET /settings/ssh_profiles" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns success" do
        get settings_ssh_profiles_path
        expect(response).to have_http_status(:success)
      end

      it "displays ssh profiles" do
        profile = create(:ssh_profile, name: "Production Servers")
        get settings_ssh_profiles_path
        expect(response.body).to include("Production Servers")
      end

      it "displays connection method" do
        profile = create(:ssh_profile, :custom_bastion)
        get settings_ssh_profiles_path
        expect(response.body).to include("Custom Bastion")
      end

      it "displays nodes count" do
        profile = create(:ssh_profile)
        create_list(:node, 3, ssh_profile: profile)
        get settings_ssh_profiles_path
        expect(response.body).to include("3")
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects to root" do
        get settings_ssh_profiles_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "when not authenticated" do
      it "redirects to sign in" do
        get settings_ssh_profiles_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /settings/ssh_profiles/new" do
    before { sign_in approver }

    it "returns success" do
      get new_settings_ssh_profile_path
      expect(response).to have_http_status(:success)
    end

    it "displays the form" do
      get new_settings_ssh_profile_path
      expect(response.body).to include("Name")
      expect(response.body).to include("SSH Port")
    end
  end

  describe "POST /settings/ssh_profiles" do
    before { sign_in approver }

    context "with valid params" do
      let(:valid_params) do
        {
          ssh_profile: {
            name: "Test Profile",
            ssh_connect_method: "global_bastion",
            ssh_port: 22,
            ssh_user: "deploy"
          }
        }
      end

      it "creates a new ssh profile" do
        expect {
          post settings_ssh_profiles_path, params: valid_params
        }.to change(SshProfile, :count).by(1)
      end

      it "redirects to index" do
        post settings_ssh_profiles_path, params: valid_params
        expect(response).to redirect_to(settings_ssh_profiles_path)
      end

      it "sets flash notice" do
        post settings_ssh_profiles_path, params: valid_params
        expect(flash[:notice]).to eq("SSH profile was successfully created.")
      end
    end

    context "with custom_bastion params" do
      let(:bastion_params) do
        {
          ssh_profile: {
            name: "Bastion Profile",
            ssh_connect_method: "custom_bastion",
            ssh_port: 22,
            ssh_user: "deploy",
            jump_host: "bastion.example.com",
            jump_user: "bastion_user",
            jump_port: 2222
          }
        }
      end

      it "creates profile with bastion fields" do
        post settings_ssh_profiles_path, params: bastion_params
        profile = SshProfile.last
        expect(profile.jump_host).to eq("bastion.example.com")
        expect(profile.jump_user).to eq("bastion_user")
        expect(profile.jump_port).to eq(2222)
      end
    end

    context "with invalid params" do
      let(:invalid_params) { { ssh_profile: { name: "" } } }

      it "does not create a ssh profile" do
        expect {
          post settings_ssh_profiles_path, params: invalid_params
        }.not_to change(SshProfile, :count)
      end

      it "renders new with unprocessable_entity" do
        post settings_ssh_profiles_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /settings/ssh_profiles/:id/edit" do
    let!(:profile) { create(:ssh_profile) }
    before { sign_in approver }

    it "returns success" do
      get edit_settings_ssh_profile_path(profile)
      expect(response).to have_http_status(:success)
    end

    it "displays current values" do
      get edit_settings_ssh_profile_path(profile)
      expect(response.body).to include(profile.name)
    end
  end

  describe "PATCH /settings/ssh_profiles/:id" do
    let!(:profile) { create(:ssh_profile) }
    before { sign_in approver }

    context "with valid params" do
      it "updates the profile" do
        patch settings_ssh_profile_path(profile), params: { ssh_profile: { name: "Updated Name" } }
        expect(profile.reload.name).to eq("Updated Name")
      end

      it "redirects to index" do
        patch settings_ssh_profile_path(profile), params: { ssh_profile: { name: "Updated Name" } }
        expect(response).to redirect_to(settings_ssh_profiles_path)
      end

      it "sets flash notice" do
        patch settings_ssh_profile_path(profile), params: { ssh_profile: { name: "Updated Name" } }
        expect(flash[:notice]).to eq("SSH profile was successfully updated.")
      end
    end

    context "with invalid params" do
      it "renders edit with unprocessable_entity" do
        patch settings_ssh_profile_path(profile), params: { ssh_profile: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /settings/ssh_profiles/:id" do
    let!(:profile) { create(:ssh_profile) }
    before { sign_in approver }

    it "deletes the profile" do
      expect {
        delete settings_ssh_profile_path(profile)
      }.to change(SshProfile, :count).by(-1)
    end

    it "redirects to index" do
      delete settings_ssh_profile_path(profile)
      expect(response).to redirect_to(settings_ssh_profiles_path)
    end

    it "sets flash notice" do
      delete settings_ssh_profile_path(profile)
      expect(flash[:notice]).to eq("SSH profile was successfully deleted.")
    end

    context "with associated nodes" do
      let!(:node) { create(:node, ssh_profile: profile) }

      it "nullifies node associations" do
        delete settings_ssh_profile_path(profile)
        expect(node.reload.ssh_profile_id).to be_nil
      end

      it "still deletes the profile" do
        expect {
          delete settings_ssh_profile_path(profile)
        }.to change(SshProfile, :count).by(-1)
      end
    end
  end
end
