# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Inventory", type: :request do
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
      node_id: node.id,
      collection_method: "redfish",
      processors: [ { socket: "CPU1", model: "Intel Xeon", cores: 16 } ],
      memory: [ { slot: "DIMM_A1", size_gb: 32, speed_mhz: 3200 } ],
      storage: [ { name: "Disk 0", capacity: "480GB", model: "Samsung SSD" } ],
      network: [ { name: "NIC1", mac: "00:11:22:33:44:55" } ],
      infiniband: [ { hca: "mlx5_0", port_state: "Active" } ],
      bios: { vendor: "AMI", version: "2.5.1" },
      bmc_info: { model: "iDRAC9", firmware: "2.10.0" }
    }
  end

  describe "POST /api/v1/bmc/inventory" do
    context "with valid token and payload" do
      it "returns 200 OK" do
        post "/api/v1/bmc/inventory",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "creates a new BmcInventory record" do
        expect {
          post "/api/v1/bmc/inventory",
               params: valid_payload.to_json,
               headers: {
                 "Authorization" => "Bearer #{valid_token}",
                 "Content-Type" => "application/json"
               }
        }.to change(BmcInventory, :count).by(1)
      end

      it "returns status ok and inventory_id in response" do
        post "/api/v1/bmc/inventory",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("ok")
        expect(json["inventory_id"]).to be_present
      end

      it "stores the correct data in the inventory" do
        post "/api/v1/bmc/inventory",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        inventory = BmcInventory.find(json["inventory_id"])

        expect(inventory.node).to eq(node)
        expect(inventory.collection_method).to eq("redfish")
        expect(inventory.processors.first["model"]).to eq("Intel Xeon")
      end
    end

    context "with node_id as uuid" do
      let(:payload_with_uuid) { valid_payload.merge(node_id: node.uuid) }

      it "returns 200 OK" do
        post "/api/v1/bmc/inventory",
             params: payload_with_uuid.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "creates inventory for the correct node" do
        post "/api/v1/bmc/inventory",
             params: payload_with_uuid.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        inventory = BmcInventory.find(json["inventory_id"])
        expect(inventory.node).to eq(node)
      end
    end

    context "with node_id as hostname" do
      let(:payload_with_hostname) { valid_payload.merge(node_id: node.hostname) }

      it "returns 200 OK" do
        post "/api/v1/bmc/inventory",
             params: payload_with_hostname.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "creates inventory for the correct node" do
        post "/api/v1/bmc/inventory",
             params: payload_with_hostname.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        inventory = BmcInventory.find(json["inventory_id"])
        expect(inventory.node).to eq(node)
      end
    end

    context "with invalid node_id" do
      let(:invalid_payload) { valid_payload.merge(node_id: 999_999) }

      it "returns 422 Unprocessable Entity" do
        post "/api/v1/bmc/inventory",
             params: invalid_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns error status and message" do
        post "/api/v1/bmc/inventory",
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
        post "/api/v1/bmc/inventory",
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
        post "/api/v1/bmc/inventory",
             params: valid_payload.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns error message" do
        post "/api/v1/bmc/inventory",
             params: valid_payload.to_json,
             headers: { "Content-Type" => "application/json" }

        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "with invalid token" do
      it "returns 401 Unauthorized" do
        post "/api/v1/bmc/inventory",
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
        post "/api/v1/bmc/inventory",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => valid_token,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with ipmi collection method" do
      let(:ipmi_payload) { valid_payload.merge(collection_method: "ipmi") }

      it "returns 200 OK" do
        post "/api/v1/bmc/inventory",
             params: ipmi_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "stores ipmi as collection_method" do
        post "/api/v1/bmc/inventory",
             params: ipmi_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        inventory = BmcInventory.find(json["inventory_id"])
        expect(inventory.collection_method).to eq("ipmi")
      end
    end

    context "with invalid collection_method" do
      let(:invalid_method_payload) { valid_payload.merge(collection_method: "invalid") }

      it "returns 422 Unprocessable Entity" do
        post "/api/v1/bmc/inventory",
             params: invalid_method_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns validation error message" do
        post "/api/v1/bmc/inventory",
             params: invalid_method_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("error")
        expect(json["message"]).to include("Collection method")
      end
    end

    context "with minimal payload" do
      let(:minimal_payload) do
        {
          node_id: node.id,
          collection_method: "redfish"
        }
      end

      it "returns 200 OK" do
        post "/api/v1/bmc/inventory",
             params: minimal_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "creates inventory with empty arrays and hashes" do
        post "/api/v1/bmc/inventory",
             params: minimal_payload.to_json,
             headers: {
               "Authorization" => "Bearer #{valid_token}",
               "Content-Type" => "application/json"
             }

        json = JSON.parse(response.body)
        inventory = BmcInventory.find(json["inventory_id"])

        expect(inventory.processors).to eq([])
        expect(inventory.memory).to eq([])
        expect(inventory.storage).to eq([])
        expect(inventory.network).to eq([])
        expect(inventory.infiniband).to eq([])
        expect(inventory.bios).to eq({})
        expect(inventory.bmc_info).to eq({})
      end
    end

    context "with ApiKey authentication" do
      let!(:api_key) { create(:api_key, token: "api-key-token") }

      it "returns 200 OK with valid ApiKey token" do
        post "/api/v1/bmc/inventory",
             params: valid_payload.to_json,
             headers: {
               "Authorization" => "Bearer api-key-token",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end

      it "updates ApiKey last_used_at" do
        expect {
          post "/api/v1/bmc/inventory",
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
