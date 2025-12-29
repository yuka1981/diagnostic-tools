# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home", type: :request do
  describe "GET /" do
    it "returns http success" do
      get root_path
      expect(response).to have_http_status(:success)
    end

    it "displays the dashboard" do
      get root_path
      expect(response.body).to include("Dashboard")
      expect(response.body).to include("HPC Diagnostics")
    end
  end
end
