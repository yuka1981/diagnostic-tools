# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Collect", type: :request do
  include ActiveJob::TestHelper

  let(:valid_token) { "test-agent-token" }
  let(:invalid_token) { "invalid-token" }
  let(:node) { create(:node) }

  before do
    # Stub the ENV variable for token authentication in tests
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("API_AGENT_TOKEN").and_return(valid_token)
  end

  describe "POST /api/v1/bmc/collect/inventory" do
    context "with valid token and node_id" do
      it "returns 200 OK" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.id }.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "returns queued status with job_id" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.id }.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("queued")
        expect(json["job_id"]).to be_present
      end

      it "returns node information in response" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.id }.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["node_id"]).to eq(node.id)
        expect(json["node_name"]).to eq(node.hostname)
      end

      it "enqueues a Bmc::CollectInventoryJob" do
        expect {
          post "/api/v1/bmc/collect/inventory",
               params: { node_id: node.id }.to_json,
               headers: {
                 "Authorization" => "Bearer #{valid_token}",
                 "Content-Type" => "application/json"
               }
        }.to have_enqueued_job(Bmc::CollectInventoryJob).with(node.id)
      end
    end

    context "with node_id as uuid" do
      it "returns 200 OK" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.uuid }.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "enqueues job for the correct node" do
        expect {
          post "/api/v1/bmc/collect/inventory",
               params: { node_id: node.uuid }.to_json,
               headers: {
                 "Authorization" => "Bearer #{valid_token}",
                 "Content-Type" => "application/json"
               }
        }.to have_enqueued_job(Bmc::CollectInventoryJob).with(node.id)

        json = JSON.parse(response.body)
        expect(json["node_id"]).to eq(node.id)
      end
    end

    context "with node_id as hostname" do
      it "returns 200 OK" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.hostname }.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "enqueues job for the correct node" do
        expect {
          post "/api/v1/bmc/collect/inventory",
               params: { node_id: node.hostname }.to_json,
               headers: {
                 "Authorization" => "Bearer #{valid_token}",
                 "Content-Type" => "application/json"
               }
        }.to have_enqueued_job(Bmc::CollectInventoryJob).with(node.id)

        json = JSON.parse(response.body)
        expect(json["node_id"]).to eq(node.id)
      end
    end

    context "with invalid node_id" do
      it "returns 404 Not Found" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: 999_999 }.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:not_found)
      end

      it "returns error message" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: 999_999 }.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Node not found")
      end

      it "does not enqueue a job" do
        expect {
          post "/api/v1/bmc/collect/inventory",
               params: { node_id: 999_999 }.to_json,
               headers: {
                 "Authorization" => "Bearer #{valid_token}",
                 "Content-Type" => "application/json"
               }
        }.not_to have_enqueued_job(Bmc::CollectInventoryJob)
      end
    end

    context "with non-existent hostname" do
      it "returns 404 Not Found" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: "non-existent-node" }.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with missing node_id" do
      it "returns 404 Not Found" do
        post "/api/v1/bmc/collect/inventory",
             params: {}.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:not_found)
      end
    end

    context "without authorization header" do
      it "returns 401 Unauthorized" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.id }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns error message" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.id }.to_json,
             headers: { "Content-Type" => "application/json" }

        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "with invalid token" do
      it "returns 401 Unauthorized" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.id }.to_json,
             headers: {
               "Authorization" => "Bearer #{invalid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with malformed authorization header" do
      it "returns 401 Unauthorized for missing Bearer prefix" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.id }.to_json,
             headers: {
               "Authorization" => valid_token,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with ApiKey authentication" do
      let!(:api_key) { create(:api_key, token: "api-key-token") }

      it "returns 200 OK with valid ApiKey token" do
        post "/api/v1/bmc/collect/inventory",
             params: { node_id: node.id }.to_json,
             headers: {
               "Authorization" => "Bearer api-key-token",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "updates ApiKey last_used_at" do
        expect {
          post "/api/v1/bmc/collect/inventory",
               params: { node_id: node.id }.to_json,
               headers: {
                 "Authorization" => "Bearer api-key-token",
                 "Content-Type" => "application/json"
               }
        }.to change { api_key.reload.last_used_at }
      end
    end
  end
end
