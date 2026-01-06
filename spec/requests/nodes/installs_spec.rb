# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Installs", type: :request do
  let(:user) { create(:user, :approver) }

  before do
    sign_in user
  end

  describe "GET /nodes/installs/new" do
    it "returns http success" do
      get new_node_install_path
      expect(response).to have_http_status(:success)
    end

    it "sets target_host from params" do
      get new_node_install_path(hostname: "compute-001")
      expect(response.body).to include('value="compute-001"')
    end
  end

  describe "POST /nodes/installs" do
    let(:install_params) do
      {
        hostname: "compute-001",
        arch: "x86_64",
        bastion_user: "admin",
        bastion_password: "password",
        sudo_password: "sudo_password"
      }
    end

    it "enqueues an Agent::InstallJob without passing passwords" do
      expect {
        post node_install_index_path, params: { install: install_params }
      }.to enqueue_job(Agent::InstallJob).with(
        hash_including(
          target_host: "compute-001",
          credentials_cache_key: kind_of(String)
        )
      )

      expect(response).to redirect_to(nodes_path)
    end

    it "enqueues an Agent::InstallJob with custom server_url if provided" do
      expect {
        post node_install_index_path, params: { install: install_params.merge(server_url: "https://custom-server.com") }
      }.to enqueue_job(Agent::InstallJob).with(
        hash_including(
          server_url: "https://custom-server.com"
        )
      )
    end

    it "returns turbo stream if requested" do
      post node_install_index_path, params: { install: install_params }, as: :turbo_stream
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include('id="agent_install_status_compute-001"')
    end
  end
end
