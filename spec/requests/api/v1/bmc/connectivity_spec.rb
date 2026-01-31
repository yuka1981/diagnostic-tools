# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Connectivity", type: :request do
  let(:api_key) { create(:api_key) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }

  describe "POST /api/v1/bmc/check_connectivity" do
    it "checks connectivity via Salt with valid token" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:check_connectivity)
        .and_return({ "success" => true, "reachable" => 3 })

      post "/api/v1/bmc/check_connectivity", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be true
    end

    it "requires authentication" do
      post "/api/v1/bmc/check_connectivity"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
