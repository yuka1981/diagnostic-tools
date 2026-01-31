# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Credentials", type: :request do
  let(:api_key) { create(:api_key) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }

  describe "GET /api/v1/bmc/credentials" do
    let!(:node1) { create(:node, hostname: "compute-001") }
    let!(:node2) { create(:node, hostname: "compute-002") }
    let!(:global) { create(:bmc_credential, :global_default, bmc_address: "default-bmc") }
    let!(:node1_cred) { create(:bmc_credential, node: node1, bmc_address: "10.0.0.1") }

    it "returns credentials for all nodes with BMC access" do
      get "/api/v1/bmc/credentials", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      creds = body["credentials"]
      expect(creds.length).to be >= 1
      node1_entry = creds.find { |c| c["hostname"] == "compute-001" }
      expect(node1_entry["bmc_address"]).to eq("10.0.0.1")
    end

    it "requires authentication" do
      get "/api/v1/bmc/credentials"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
