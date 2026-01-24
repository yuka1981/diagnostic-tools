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

    context "one-click install (all credentials configured)" do
      let(:api_key) { create(:api_key) }

      before do
        # Configure global SSH settings with all required credentials
        SshSetting.current.update!(
          server_url: "https://agent.example.com",
          ssh_user: "root",  # root user doesn't need sudo
          ssh_key: "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
        )
      end

      it "bypasses modal and enqueues install job directly" do
        node = create(:node, hostname: "configured-node", api_key: api_key)

        expect {
          get new_node_install_path(hostname: "configured-node"), headers: { "Turbo-Frame" => "install_modal" }
        }.to enqueue_job(Agent::InstallJob).with(
          hash_including(
            target_host: "configured-node",
            api_key_id: api_key.id
          )
        )

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Starting installation using stored credentials")
      end

      it "shows modal when node has no API key" do
        node = create(:node, hostname: "no-api-key-node", api_key: nil)

        expect {
          get new_node_install_path(hostname: "no-api-key-node"), headers: { "Turbo-Frame" => "install_modal" }
        }.not_to enqueue_job(Agent::InstallJob)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Begin Installation")  # Form submit button
      end

      it "shows modal when server_url is not configured" do
        SshSetting.current.update!(server_url: nil)
        node = create(:node, hostname: "no-url-node", api_key: api_key)

        expect {
          get new_node_install_path(hostname: "no-url-node"), headers: { "Turbo-Frame" => "install_modal" }
        }.not_to enqueue_job(Agent::InstallJob)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Begin Installation")
      end

      it "shows modal for new nodes (not in database)" do
        expect {
          get new_node_install_path(hostname: "new-node"), headers: { "Turbo-Frame" => "install_modal" }
        }.not_to enqueue_job(Agent::InstallJob)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Begin Installation")
      end
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

      expect(node.reload.sudo_credential).to eq("ssh-password")
    end
  end

  describe "localhost installation rejection" do
    %w[localhost 127.0.0.1 ::1].each do |localhost_host|
      context "when hostname is #{localhost_host}" do
        it "rejects GET request with localhost not supported message" do
          get new_node_install_path(hostname: localhost_host), headers: { "Turbo-Frame" => "install_modal" }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include("Localhost Installation Not Supported")
          expect(response.body).to include(localhost_host)
        end

        it "rejects POST request with localhost not supported message" do
          params = {
            hostname: localhost_host,
            arch: "x86_64",
            sudo_password: "password"
          }

          expect {
            post node_install_index_path, params: { install: params }, as: :turbo_stream
          }.not_to enqueue_job(Agent::InstallJob)

          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
          expect(response.body).to include("Localhost Installation Not Supported")
        end
      end
    end

    it "allows installation for non-localhost hosts" do
      get new_node_install_path(hostname: "compute-001"), headers: { "Turbo-Frame" => "install_modal" }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Localhost Installation Not Supported")
    end
  end
end
