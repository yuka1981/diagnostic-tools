# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Collect", type: :request do
  let(:api_key) { create(:api_key) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }

  describe "POST /api/v1/bmc/collect/sensors" do
    it "triggers sensor collection via Salt" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_sensors)
        .and_return({ "success" => true, "collected" => 5 })

      post "/api/v1/bmc/collect/sensors", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be true
    end

    it "accepts optional node parameter" do
      trigger = instance_double(Bmc::SaltTriggerService)
      allow(Bmc::SaltTriggerService).to receive(:new).and_return(trigger)
      expect(trigger).to receive(:collect_sensors).with(node: "compute-001")
        .and_return({ "success" => true })

      post "/api/v1/bmc/collect/sensors", params: { node: "compute-001" }, headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "requires authentication" do
      post "/api/v1/bmc/collect/sensors"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/bmc/collect/inventory" do
    it "triggers inventory collection via Salt" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_inventory)
        .and_return({ "success" => true, "collected" => 5 })

      post "/api/v1/bmc/collect/inventory", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "requires authentication" do
      post "/api/v1/bmc/collect/inventory"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
