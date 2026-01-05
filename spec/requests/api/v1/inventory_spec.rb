# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Inventory", type: :request do
  let(:valid_token) { "test-agent-token" }
  let(:invalid_token) { "invalid-token" }
  let(:node) { create(:node) }

  before do
    # Stub the ENV variable for token authentication in tests
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("API_AGENT_TOKEN").and_return(valid_token)
  end

  let(:valid_payload) do
    {
      host: { hostname: node.hostname, os: "linux", platform: "ubuntu" },
      cpu: { "model" => "Intel Xeon", "cores" => 16 },
      memory: { "total" => 64.gigabytes },
      disks: [ { "device" => "/dev/sda", "total" => 500.gigabytes } ],
      network: [ { "interface" => "eth0", "ip" => "192.168.1.100" } ]
    }
  end

  describe "POST /api/v1/inventory/push" do
    context "with valid token and payload" do
      it "returns 200 OK" do
        post "/api/v1/inventory/push",
          params: valid_payload.to_json,
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:ok)
      end

      it "creates a new NodeState" do
        expect {
          post "/api/v1/inventory/push",
            params: valid_payload.to_json,
            headers: {
              "Authorization" => "Bearer #{valid_token}",
              "Content-Type" => "application/json"
            }
        }.to change(NodeState, :count).by(1)
      end

      it "returns state_created in response" do
        post "/api/v1/inventory/push",
          params: valid_payload.to_json,
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["state_created"]).to be true
      end

      it "updates node last_seen_at" do
        expect {
          post "/api/v1/inventory/push",
            params: valid_payload.to_json,
            headers: {
              "Authorization" => "Bearer #{valid_token}",
              "Content-Type" => "application/json"
            }
        }.to change { node.reload.last_seen_at }
      end
    end

    context "with valid token but same content (no state change)" do
      before do
        create(:node_state,
          node: node,
          host_info: valid_payload[:host],
          cpu_info: valid_payload[:cpu],
          mem_info: valid_payload[:memory],
          disk_info: valid_payload[:disks],
          net_info: valid_payload[:network],
          captured_at: 1.hour.ago
        )
      end

      it "returns 200 OK with state_created false" do
        post "/api/v1/inventory/push",
          params: valid_payload.to_json,
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["state_created"]).to be false
      end

      it "does not create a new NodeState" do
        expect {
          post "/api/v1/inventory/push",
            params: valid_payload.to_json,
            headers: {
              "Authorization" => "Bearer #{valid_token}",
              "Content-Type" => "application/json"
            }
        }.not_to change(NodeState, :count)
      end
    end

    context "without authorization header" do
      it "returns 401 Unauthorized" do
        post "/api/v1/inventory/push",
          params: valid_payload.to_json,
          headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns error message" do
        post "/api/v1/inventory/push",
          params: valid_payload.to_json,
          headers: { "Content-Type" => "application/json" }

        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "with invalid token" do
      it "returns 401 Unauthorized" do
        post "/api/v1/inventory/push",
          params: valid_payload.to_json,
          headers: {
            "Authorization" => "Bearer #{invalid_token}",
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with malformed authorization header" do
      it "returns 401 Unauthorized for missing Bearer prefix" do
        post "/api/v1/inventory/push",
          params: valid_payload.to_json,
          headers: {
            "Authorization" => valid_token,
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with missing hostname" do
      let(:invalid_payload) { valid_payload.except(:host) }

      it "returns 400 Bad Request" do
        post "/api/v1/inventory/push",
          params: invalid_payload.to_json,
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:bad_request)
      end

      it "returns error message" do
        post "/api/v1/inventory/push",
          params: invalid_payload.to_json,
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        json = JSON.parse(response.body)
        expect(json["error"]).to include("required")
      end
    end

    context "with non-existent hostname" do
      let(:payload) { valid_payload.deep_merge(host: { hostname: "ghost-node" }) }

      it "returns 404 Not Found" do
        post "/api/v1/inventory/push",
          params: payload.to_json,
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with invalid JSON" do
      it "returns 400 Bad Request" do
        post "/api/v1/inventory/push",
          params: "{ invalid json }",
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with empty body" do
      it "returns 400 Bad Request" do
        post "/api/v1/inventory/push",
          params: "",
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with node_id instead of hostname" do
      let(:payload) { valid_payload.except(:host).merge(node_id: node.id) }

      it "returns 200 OK" do
        post "/api/v1/inventory/push",
          params: payload.to_json,
          headers: {
            "Authorization" => "Bearer #{valid_token}",
            "Content-Type" => "application/json"
          }

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
