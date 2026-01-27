# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Sensors", type: :request do
  let(:valid_token) { "test-agent-token" }
  let(:invalid_token) { "invalid-token" }
  let(:node) { create(:node, hostname: "test-node-001") }
  let(:pushgateway_url) { "http://pushgateway.example.com:9091" }

  before do
    # Stub the ENV variable for token authentication in tests
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("API_AGENT_TOKEN").and_return(valid_token)

    # Configure pushgateway URL
    SshSetting.current.update!(prometheus_pushgateway_url: pushgateway_url)
  end

  let(:valid_payload) do
    {
      node_id: node.id,
      sensors: [
        { name: "CPU Temp", value: 45.5, unit: "Celsius", status: "OK" },
        { name: "System Fan 1", value: 3200, unit: "RPM", status: "OK" },
        { name: "Power Supply", value: 250, unit: "Watts", status: "Warning" }
      ]
    }
  end

  describe "POST /api/v1/bmc/sensors" do
    context "with valid token and payload" do
      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns 200 OK" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "returns status ok in response" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("ok")
      end

      it "pushes metrics to Pushgateway" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(
          a_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
        ).to have_been_made.once
      end
    end

    context "with node_id as uuid" do
      let(:payload_with_uuid) { valid_payload.merge(node_id: node.uuid) }

      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns 200 OK" do
        post "/api/v1/bmc/sensors",
             params: payload_with_uuid.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with node_id as hostname" do
      let(:payload_with_hostname) { valid_payload.merge(node_id: node.hostname) }

      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns 200 OK" do
        post "/api/v1/bmc/sensors",
             params: payload_with_hostname.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid node_id" do
      let(:invalid_payload) { valid_payload.merge(node_id: 999_999) }

      it "returns 422 Unprocessable Entity" do
        post "/api/v1/bmc/sensors",
             params: invalid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns error status and message" do
        post "/api/v1/bmc/sensors",
             params: invalid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("error")
        expect(json["message"]).to eq("Node not found")
      end
    end

    context "with non-existent hostname" do
      let(:invalid_payload) { valid_payload.merge(node_id: "non-existent-node") }

      it "returns 422 Unprocessable Entity" do
        post "/api/v1/bmc/sensors",
             params: invalid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "without authorization header" do
      it "returns 401 Unauthorized" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns error message" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: { "Content-Type" => "application/json" }

        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "with invalid token" do
      it "returns 401 Unauthorized" do
        post "/api/v1/bmc/sensors",
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
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => valid_token,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when Pushgateway URL is not configured" do
      before do
        SshSetting.current.update!(prometheus_pushgateway_url: nil)
      end

      it "returns 422 Unprocessable Entity" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns error about missing configuration" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("error")
        expect(json["message"]).to eq("Pushgateway URL not configured")
      end
    end

    context "when Pushgateway returns an error" do
      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 500, body: "Internal Server Error", headers: {})
      end

      it "returns 422 Unprocessable Entity" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns error with Pushgateway response" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("error")
        expect(json["message"]).to include("Pushgateway returned 500")
      end
    end

    context "with empty sensors array" do
      let(:empty_sensors_payload) do
        {
          node_id: node.id,
          sensors: []
        }
      end

      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns 200 OK" do
        post "/api/v1/bmc/sensors",
             params: empty_sensors_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with ApiKey authentication" do
      let!(:api_key) { create(:api_key, token: "api-key-token") }

      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns 200 OK with valid ApiKey token" do
        post "/api/v1/bmc/sensors",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer api-key-token",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "updates ApiKey last_used_at" do
        expect {
          post "/api/v1/bmc/sensors",
               params: valid_payload.to_json,
               headers: {
                 "Authorization" => "Bearer api-key-token",
                 "Content-Type" => "application/json"
               }
        }.to change { api_key.reload.last_used_at }
      end
    end
  end
end
