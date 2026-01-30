# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Heartbeats" do
  let!(:api_key) { create(:api_key) }
  let(:headers) do
    {
      "Authorization" => "Bearer #{api_key.token}",
      "Content-Type" => "application/json"
    }
  end
  let!(:node) { create(:node, uuid: "fc722df8-c5d7-4a17-b451-076f91f6002e") }

  describe "POST /api/v1/nodes/:uuid/heartbeat" do
    let(:payload) do
      {
        uuid: node.uuid,
        timestamp: Time.current.iso8601,
        version: "1.2.0",
        status: "idle"
      }
    end

    it "updates last_heartbeat_at and returns ok" do
      expect {
        post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: headers
      }.to change { node.reload.last_heartbeat_at }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("ok")
    end

    it "updates agent_version when provided" do
      post "/api/v1/nodes/#{node.uuid}/heartbeat", params: payload.to_json, headers: headers

      expect(node.reload.agent_version).to eq("1.2.0")
    end

    it "returns 404 for unknown uuid" do
      post "/api/v1/nodes/nonexistent/heartbeat", params: payload.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without auth token" do
      post "/api/v1/nodes/#{node.uuid}/heartbeat",
           params: payload.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
