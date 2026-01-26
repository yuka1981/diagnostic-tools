# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::ServerProducts", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /api/server_products/search" do
    let!(:product1) { create(:server_product, name: "QuantaGrid D54Q-2U") }
    let!(:product2) { create(:server_product, name: "QuantaPlex T42S-2U") }
    let!(:product3) { create(:server_product, name: "QuantaGrid S74G-2U") }

    it "returns matching products" do
      get search_api_server_products_path, params: { q: "QuantaGrid" }
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.size).to eq(2)
      expect(json.map { |p| p["name"] }).to include("QuantaGrid D54Q-2U", "QuantaGrid S74G-2U")
    end

    it "returns empty array for no matches" do
      get search_api_server_products_path, params: { q: "NonExistent" }
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json).to be_empty
    end

    it "limits results to 10" do
      12.times { |i| create(:server_product, name: "QuantaGrid Model-#{i}") }
      get search_api_server_products_path, params: { q: "QuantaGrid" }
      json = JSON.parse(response.body)
      expect(json.size).to be <= 10
    end

    it "includes required fields" do
      get search_api_server_products_path, params: { q: "D54Q" }
      json = JSON.parse(response.body)
      expect(json.first).to include(
        "id", "name", "form_factor", "rack_height"
      )
    end
  end

  describe "GET /api/server_products" do
    before do
      create(:server_product, name: "QuantaGrid 1U", form_factor: "1U")
      create(:server_product, name: "QuantaGrid 2U", form_factor: "2U")
      create(:server_product, :quantaplex, form_factor: "2U")
    end

    it "returns all products" do
      get api_server_products_path
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.size).to eq(3)
    end

    it "filters by form factor" do
      get api_server_products_path, params: { form_factor: "2U" }
      json = JSON.parse(response.body)
      expect(json.size).to eq(2)
    end

    it "filters by series" do
      get api_server_products_path, params: { series: "QuantaPlex" }
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
    end
  end
end
