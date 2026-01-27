# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Nodes", type: :request do
  let(:valid_token) { "test-agent-token" }
  let(:invalid_token) { "invalid-token" }

  before do
    # Stub the ENV variable for token authentication in tests
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("API_AGENT_TOKEN").and_return(valid_token)
  end

  describe "GET /api/v1/bmc/nodes" do
    context "with valid token" do
      it "returns 200 OK" do
        get "/api/v1/bmc/nodes",
            headers: { "Authorization" => "Bearer #{valid_token}" }

        expect(response).to have_http_status(:ok)
      end

      it "returns an empty array when no nodes with bmc_address exist" do
        create(:node) # Node without bmc_address

        get "/api/v1/bmc/nodes",
            headers: { "Authorization" => "Bearer #{valid_token}" }

        json = JSON.parse(response.body)
        expect(json).to eq([])
      end

      context "with nodes having bmc_address" do
        let!(:node_with_bmc) { create(:node, bmc_address: "192.168.1.100") }
        let!(:node_without_bmc) { create(:node, bmc_address: nil) }
        let!(:node_with_empty_bmc) { create(:node, bmc_address: "") }

        it "returns only nodes with bmc_address" do
          get "/api/v1/bmc/nodes",
              headers: { "Authorization" => "Bearer #{valid_token}" }

          json = JSON.parse(response.body)
          expect(json.length).to eq(1)
          expect(json.first["id"]).to eq(node_with_bmc.id)
        end

        it "returns expected response format" do
          get "/api/v1/bmc/nodes",
              headers: { "Authorization" => "Bearer #{valid_token}" }

          json = JSON.parse(response.body)
          node_data = json.first

          expect(node_data).to include(
            "id" => node_with_bmc.id,
            "bmc_address" => "192.168.1.100",
            "bmc_protocol" => "auto"
          )
          expect(node_data).to have_key("node_id")
          expect(node_data).to have_key("name")
          expect(node_data).to have_key("bmc_username")
          expect(node_data).to have_key("bmc_password")
          expect(node_data).to have_key("bmc_port")
          expect(node_data).to have_key("bmc_verify_ssl")
        end
      end

      context "with node-specific BMC credential" do
        let!(:node) { create(:node, bmc_address: "192.168.1.100") }
        let!(:node_credential) do
          create(:bmc_credential,
                 node: node,
                 bmc_address: "192.168.1.100",
                 username: "node_admin",
                 password: "node_secret",
                 protocol: :redfish,
                 port: 443,
                 verify_ssl: false)
        end

        it "returns node-specific credentials" do
          get "/api/v1/bmc/nodes",
              headers: { "Authorization" => "Bearer #{valid_token}" }

          json = JSON.parse(response.body)
          node_data = json.first

          expect(node_data["bmc_username"]).to eq("node_admin")
          expect(node_data["bmc_password"]).to eq("node_secret")
          expect(node_data["bmc_protocol"]).to eq("redfish")
          expect(node_data["bmc_port"]).to eq(443)
          expect(node_data["bmc_verify_ssl"]).to eq(false)
        end
      end

      context "with global default BMC credential" do
        let!(:node) { create(:node, bmc_address: "192.168.1.100") }
        let!(:global_credential) do
          create(:bmc_credential, :global_default,
                 bmc_address: "default",
                 username: "global_admin",
                 password: "global_secret",
                 protocol: :ipmi,
                 port: 623,
                 verify_ssl: true)
        end

        it "returns global default credentials when node has no specific credential" do
          get "/api/v1/bmc/nodes",
              headers: { "Authorization" => "Bearer #{valid_token}" }

          json = JSON.parse(response.body)
          node_data = json.first

          expect(node_data["bmc_username"]).to eq("global_admin")
          expect(node_data["bmc_password"]).to eq("global_secret")
          expect(node_data["bmc_protocol"]).to eq("ipmi")
          expect(node_data["bmc_port"]).to eq(623)
          expect(node_data["bmc_verify_ssl"]).to eq(true)
        end
      end

      context "with node-specific credential taking precedence over global" do
        let!(:node) { create(:node, bmc_address: "192.168.1.100") }
        let!(:global_credential) do
          create(:bmc_credential, :global_default,
                 bmc_address: "default",
                 username: "global_admin",
                 password: "global_secret")
        end
        let!(:node_credential) do
          create(:bmc_credential,
                 node: node,
                 bmc_address: "192.168.1.100",
                 username: "node_admin",
                 password: "node_secret")
        end

        it "returns node-specific credentials over global default" do
          get "/api/v1/bmc/nodes",
              headers: { "Authorization" => "Bearer #{valid_token}" }

          json = JSON.parse(response.body)
          node_data = json.first

          expect(node_data["bmc_username"]).to eq("node_admin")
          expect(node_data["bmc_password"]).to eq("node_secret")
        end
      end

      context "with no BMC credentials configured" do
        let!(:node) { create(:node, bmc_address: "192.168.1.100") }

        it "returns nil for credential fields" do
          get "/api/v1/bmc/nodes",
              headers: { "Authorization" => "Bearer #{valid_token}" }

          json = JSON.parse(response.body)
          node_data = json.first

          expect(node_data["bmc_username"]).to be_nil
          expect(node_data["bmc_password"]).to be_nil
          expect(node_data["bmc_protocol"]).to eq("auto")
          expect(node_data["bmc_port"]).to be_nil
          expect(node_data["bmc_verify_ssl"]).to be_nil
        end
      end

      context "with multiple nodes" do
        before do
          create_list(:node, 3, bmc_address: "192.168.1.100")
          create_list(:node, 2, bmc_address: nil)
        end

        it "returns all nodes with bmc_address" do
          get "/api/v1/bmc/nodes",
              headers: { "Authorization" => "Bearer #{valid_token}" }

          json = JSON.parse(response.body)
          expect(json.length).to eq(3)
        end
      end
    end

    context "without authorization header" do
      it "returns 401 Unauthorized" do
        get "/api/v1/bmc/nodes"

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns error message" do
        get "/api/v1/bmc/nodes"

        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "with invalid token" do
      it "returns 401 Unauthorized" do
        get "/api/v1/bmc/nodes",
            headers: { "Authorization" => "Bearer #{invalid_token}" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with malformed authorization header" do
      it "returns 401 Unauthorized for missing Bearer prefix" do
        get "/api/v1/bmc/nodes",
            headers: { "Authorization" => valid_token }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 Unauthorized for empty authorization header" do
        get "/api/v1/bmc/nodes",
            headers: { "Authorization" => "" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with ApiKey authentication" do
      let!(:api_key) { create(:api_key, token: "api-key-token") }

      it "returns 200 OK with valid ApiKey token" do
        create(:node, bmc_address: "192.168.1.100")

        get "/api/v1/bmc/nodes",
            headers: { "Authorization" => "Bearer api-key-token" }

        expect(response).to have_http_status(:ok)
      end

      it "updates ApiKey last_used_at" do
        create(:node, bmc_address: "192.168.1.100")

        expect {
          get "/api/v1/bmc/nodes",
              headers: { "Authorization" => "Bearer api-key-token" }
        }.to change { api_key.reload.last_used_at }
      end
    end
  end
end
