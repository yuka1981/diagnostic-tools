# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Uninstalls", type: :request do
  let(:user) { create(:user, :approver) }

  before do
    sign_in user
  end

  describe "GET /nodes/uninstalls/new" do
    it "returns http success" do
      get new_node_uninstall_path, headers: { "Turbo-Frame" => "uninstall_modal" }
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("<!DOCTYPE html>")
    end

    it "sets target_host from params" do
      get new_node_uninstall_path(hostname: "compute-001"), headers: { "Turbo-Frame" => "uninstall_modal" }
      expect(response.body).to include('value="compute-001"')
    end
  end

  describe "POST /nodes/uninstalls" do
    let(:uninstall_params) do
      {
        hostname: "compute-001",
        bastion_user: "admin",
        bastion_password: "password",
        sudo_password: "sudo_password"
      }
    end

    it "enqueues an Agent::UninstallJob without passing passwords" do
      expect {
        post node_uninstall_index_path, params: { uninstall: uninstall_params }
      }.to enqueue_job(Agent::UninstallJob).with(
        hash_including(
          target_host: "compute-001",
          credentials_cache_key: kind_of(String)
        )
      )

      expect(response).to redirect_to(nodes_path)
    end

    it "returns turbo stream if requested" do
      post node_uninstall_index_path, params: { uninstall: uninstall_params }, as: :turbo_stream
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include('id="agent_uninstall_status_compute-001"')
    end
  end
end
