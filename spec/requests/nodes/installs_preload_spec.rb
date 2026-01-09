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

      get new_node_install_path(hostname: "arm-node"), headers: { "Turbo-Frame" => "install_modal" }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("<!DOCTYPE html>")
      # Use a more flexible check for the hidden field
      expect(response.body).to include('name="install[arch]"')
      expect(response.body).to include('value="arm64"')
    end

    it "preloads arch from node (x86_64)" do
      create(:node, hostname: "intel-node", arch: "x86_64")

      get new_node_install_path(hostname: "intel-node"), headers: { "Turbo-Frame" => "install_modal" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('name="install[arch]"')
      expect(response.body).to include('value="x86_64"')
    end

    it "falls back to params if node arch is missing" do
      create(:node, hostname: "blank-node", arch: nil)

      get new_node_install_path(hostname: "blank-node", arch: "arm64"), headers: { "Turbo-Frame" => "install_modal" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('name="install[arch]"')
      expect(response.body).to include('value="arm64"')
    end
  end
end
