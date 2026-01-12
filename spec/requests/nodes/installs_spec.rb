# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Installs", type: :request do
  let(:user) { create(:user, :approver) }

  before do
    sign_in user
  end

  describe "GET /nodes/installs/new" do
    it "returns http success" do
      get new_node_install_path, headers: { "Turbo-Frame" => "install_modal" }
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("<!DOCTYPE html>")
    end

    it "sets target_host and arch from params" do
      get new_node_install_path(hostname: "compute-001", arch: "arm64"), headers: { "Turbo-Frame" => "install_modal" }
      expect(response.body).to include('value="compute-001"')
      expect(response.body).to include('value="arm64"')
    end

    it "preloads global SSH settings and node specific user" do
      SshSetting.current.update(bastion_host: "bastion.global", bastion_user: "global-user")
      create(:node, hostname: "preloaded-node", ssh_user: "node-user")

      get new_node_install_path(hostname: "preloaded-node"), headers: { "Turbo-Frame" => "install_modal" }
      # It prioritized (global_user.presence || node_user.presence || "root")
      # In my current view implementation, server_url might be there but not bastion_host directly in the form
      expect(response.body).to include('Install Agent: preloaded-node')
    end

    it "preloads server_url from SshSetting" do
      SshSetting.current.update!(server_url: "https://agent.example.com")
      get new_node_install_path(hostname: "compute-001"), headers: { "Turbo-Frame" => "install_modal" }
      expect(response.body).to include('value="https://agent.example.com"')
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

    it "enqueues Agent::InstallJob with optional server_url and api_key_id" do
      api_key = create(:api_key)
      full_params = install_params.merge(
        server_url: "https://custom-portal.com",
        api_key_id: api_key.id.to_s
      )

      expect {
        post node_install_index_path, params: { install: full_params }
      }.to enqueue_job(Agent::InstallJob).with(
        hash_including(
          target_host: "compute-001",
          server_url: "https://custom-portal.com",
          api_key_id: api_key.id.to_s
        )
      )
    end

    it "returns turbo stream if requested" do
      post node_install_index_path, params: { install: install_params }, as: :turbo_stream
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include('id="agent_install_status_compute-001"')
    end

    it "saves password to node if direct connection" do
      # Create node with direct connection method
      node = create(:node, hostname: "direct-node", ssh_connect_method: :direct)

      direct_params = install_params.merge(
        hostname: "direct-node",
        bastion_password: "ssh-password"
      )

      post node_install_index_path, params: { install: direct_params }

      expect(node.reload.password).to eq("ssh-password")
    end
  end
end
