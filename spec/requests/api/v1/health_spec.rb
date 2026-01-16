# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Health", type: :request do
  describe "GET /api/v1/health" do
    context "without authentication" do
      it "returns unauthorized" do
        get api_v1_health_path
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid token" do
      it "returns unauthorized" do
        get api_v1_health_path, headers: { "Authorization" => "Bearer invalid_token" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid API key token" do
      let!(:api_key) { create(:api_key, token: "valid_token_123") }

      it "returns http success" do
        get api_v1_health_path, headers: { "Authorization" => "Bearer valid_token_123" }
        expect(response).to have_http_status(:success)
      end

      it "returns JSON response" do
        get api_v1_health_path, headers: { "Authorization" => "Bearer valid_token_123" }
        expect(response.content_type).to include("application/json")
      end

      it "includes status ok" do
        get api_v1_health_path, headers: { "Authorization" => "Bearer valid_token_123" }
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("ok")
      end

      it "includes timestamp" do
        get api_v1_health_path, headers: { "Authorization" => "Bearer valid_token_123" }
        json = JSON.parse(response.body)
        expect(json["timestamp"]).to be_present
      end

      it "includes message" do
        get api_v1_health_path, headers: { "Authorization" => "Bearer valid_token_123" }
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("API is reachable and token is valid")
      end
    end
  end
end
