require "rails_helper"

RSpec.describe "Api::V1::MlcInstallations", type: :request do
  let(:api_key) { create(:api_key) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }
  let(:installation) { create(:mlc_installation, :running) }
  let(:node) { create(:node, :online, :direct) }
  let!(:installation_node) { create(:mlc_installation_node, :running, mlc_installation: installation, node: node) }

  describe "POST /api/v1/mlc_installations/:uuid/progress" do
    let(:params) do
      {
        node_id: node.uuid,
        step: 4,
        total_steps: 7,
        step_name: "Installing binary",
        status: "running"
      }
    end

    it "updates node progress" do
      post "/api/v1/mlc_installations/#{installation.uuid}/progress", params: params, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      installation_node.reload
      expect(installation_node.step_current).to eq(4)
      expect(installation_node.step_name).to eq("Installing binary")
    end

    it "returns 401 without auth token" do
      post "/api/v1/mlc_installations/#{installation.uuid}/progress", params: params, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 for unknown installation" do
      post "/api/v1/mlc_installations/unknown-uuid/progress", params: params, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/mlc_installations/:uuid/complete" do
    context "with success status" do
      let(:params) do
        {
          node_id: node.uuid,
          status: "success",
          detected_version: "3.11",
          install_path: "/opt/qct/utils/qis/software/mlc-3.11",
          module_path: "/opt/qct/utils/qis/modulefiles/mlc/3.11"
        }
      end

      it "marks node as successful" do
        post "/api/v1/mlc_installations/#{installation.uuid}/complete", params: params, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        installation_node.reload
        expect(installation_node.status).to eq("success")
      end

      it "updates detected version on installation" do
        post "/api/v1/mlc_installations/#{installation.uuid}/complete", params: params, headers: headers, as: :json

        installation.reload
        expect(installation.detected_version).to eq("3.11")
      end

      it "sets completed_at timestamp" do
        post "/api/v1/mlc_installations/#{installation.uuid}/complete", params: params, headers: headers, as: :json

        installation_node.reload
        expect(installation_node.completed_at).to be_present
      end
    end

    context "with failed status" do
      let(:params) do
        {
          node_id: node.uuid,
          status: "failed",
          error_message: "Permission denied",
          failed_at_step: 4,
          failed_step_name: "Installing binary"
        }
      end

      it "marks node as failed with error message" do
        post "/api/v1/mlc_installations/#{installation.uuid}/complete", params: params, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        installation_node.reload
        expect(installation_node.status).to eq("failed")
        expect(installation_node.error_message).to eq("Permission denied")
      end
    end
  end
end
