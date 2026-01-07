# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Installs Preloading", type: :request do
  let(:approver) { create(:user, :approver) }

  before do
    sign_in approver
  end

  describe "GET /nodes/installs/new" do
    it "preloads arch from node and normalizes aarch64 to arm64" do
      create(:node, hostname: "arm-node", arch: "aarch64")
      
      get new_node_install_path(hostname: "arm-node")
      
      expect(response).to have_http_status(:success)
      # Check if "arm64" option is selected
      expect(response.body).to include('<option selected="selected" value="arm64">arm64</option>')
    end

    it "preloads arch from node (x86_64)" do
      create(:node, hostname: "intel-node", arch: "x86_64")
      
      get new_node_install_path(hostname: "intel-node")
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<option selected="selected" value="x86_64">x86_64</option>')
    end

    it "falls back to params if node arch is missing" do
      create(:node, hostname: "blank-node", arch: nil)
      
      get new_node_install_path(hostname: "blank-node", arch: "arm64")
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<option selected="selected" value="arm64">arm64</option>')
    end
  end
end
