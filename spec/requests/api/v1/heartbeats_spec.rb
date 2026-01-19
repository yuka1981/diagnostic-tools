# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Heartbeats", type: :request do
  let(:api_key) { create(:api_key) }
  let(:node) { create(:node) }
  let(:headers) do
    {
      "Authorization" => "Bearer #{api_key.token}",
      "Content-Type" => "application/json"
    }
  end

  describe "POST /api/v1/nodes/:id/heartbeat" do
    let(:payload) do
      {
        uuid: node.uuid,
        timestamp: Time.current.iso8601,
        version: "1.2.3",
        status: "idle"
      }
    end

    context "with valid authentication" do
      it "returns 200 OK" do
        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: headers
        expect(response).to have_http_status(:ok)
      end

      it "updates last_heartbeat_at" do
        expect {
          post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: headers
        }.to change { node.reload.last_heartbeat_at }
        expect(node.reload.last_heartbeat_at).to be_within(1.second).of(Time.current)
      end

      it "updates agent_version from payload" do
        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: headers
        expect(node.reload.agent_version).to eq("1.2.3")
      end

      it "updates agent_status from payload" do
        busy_payload = payload.merge(status: "busy")
        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: busy_payload.to_json, headers: headers
        expect(node.reload.agent_status).to eq("busy")
      end

      it "returns JSON with status ok" do
        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: headers
        expect(JSON.parse(response.body)).to eq({ "status" => "ok" })
      end

      it "marks node as online" do
        node.update!(last_heartbeat_at: nil)
        expect(node).not_to be_online

        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: headers

        expect(node.reload).to be_online
      end
    end

    context "with invalid node UUID" do
      it "returns 404 Not Found" do
        post "/api/v1/nodes/nonexistent-uuid/heartbeat", params: payload.to_json, headers: headers
        expect(response).to have_http_status(:not_found)
      end

      it "returns error message" do
        post "/api/v1/nodes/nonexistent-uuid/heartbeat", params: payload.to_json, headers: headers
        expect(JSON.parse(response.body)).to eq({ "error" => "Node not found" })
      end
    end

    context "without authentication" do
      it "returns 401 Unauthorized" do
        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid token" do
      it "returns 401 Unauthorized" do
        invalid_headers = headers.merge("Authorization" => "Bearer invalid-token")
        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: invalid_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with revoked API key" do
      before { api_key.revoked! }

      it "returns 401 Unauthorized" do
        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
