# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Updates", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:regular_user) { create(:user) }
  let(:node) { create(:node, :direct) }
  let(:agent_release) { create(:agent_release, version: "v1.0.0") }
  let(:recipe) { create(:benchmark_recipe) }

  describe "GET /nodes/:node_id/update/new" do
    context "when not authenticated" do
      it "redirects to login" do
        get new_node_update_path(node)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated as regular user" do
      before { sign_in regular_user }

      it "redirects with unauthorized message" do
        get new_node_update_path(node)
        expect(response).to redirect_to(nodes_path)
        follow_redirect!
        expect(response.body).to include("not authorized")
      end
    end

    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns http success" do
        get new_node_update_path(node)
        expect(response).to have_http_status(:success)
      end

      it "assigns agent releases" do
        create(:agent_release, version: "v2.0.0")
        get new_node_update_path(node)
        expect(response.body).to include("v1.0.0")
        expect(response.body).to include("v2.0.0")
      end
    end
  end

  describe "POST /nodes/:node_id/update" do
    context "when not authenticated" do
      it "redirects to login" do
        post node_update_path(node), params: { agent_release_id: agent_release.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated as regular user" do
      before { sign_in regular_user }

      it "redirects with unauthorized message" do
        post node_update_path(node), params: { agent_release_id: agent_release.id }
        expect(response).to redirect_to(nodes_path)
      end
    end

    context "when authenticated as approver" do
      before { sign_in approver }

      it "enqueues an UpdateJob" do
        expect {
          post node_update_path(node), params: { agent_release_id: agent_release.id }
        }.to have_enqueued_job(Agent::UpdateJob).with(
          node: node,
          agent_release: agent_release,
          force: false,
          credentials_cache_key: nil
        )
      end

      it "responds with turbo_stream" do
        post node_update_path(node), params: { agent_release_id: agent_release.id },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("turbo-stream")
        expect(response.body).to include("agent_update_status_#{node.id}")
      end

      it "stores sudo password in cache when provided" do
        post node_update_path(node), params: {
          agent_release_id: agent_release.id,
          sudo_password: "secret123"
        }

        # Verify job was enqueued with a credentials cache key
        expect(Agent::UpdateJob).to have_been_enqueued.with(hash_including(
          node: node,
          agent_release: agent_release,
          credentials_cache_key: kind_of(String)
        ))
      end

      it "stores ssh password in cache when provided" do
        post node_update_path(node), params: {
          agent_release_id: agent_release.id,
          ssh_password: "ssh_secret456"
        }

        # Verify job was enqueued with a credentials cache key
        expect(Agent::UpdateJob).to have_been_enqueued.with(hash_including(
          node: node,
          agent_release: agent_release,
          credentials_cache_key: kind_of(String)
        ))
      end

      it "stores both sudo and ssh passwords when provided" do
        post node_update_path(node), params: {
          agent_release_id: agent_release.id,
          sudo_password: "sudo123",
          ssh_password: "ssh456"
        }

        expect(Agent::UpdateJob).to have_been_enqueued.with(hash_including(
          credentials_cache_key: kind_of(String)
        ))
      end

      context "when node is busy" do
        before do
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending)
        end

        it "enqueues job without force flag by default" do
          expect {
            post node_update_path(node), params: { agent_release_id: agent_release.id }
          }.to have_enqueued_job(Agent::UpdateJob).with(hash_including(force: false))
        end

        it "enqueues job with force flag when specified" do
          expect {
            post node_update_path(node), params: { agent_release_id: agent_release.id, force: "true" }
          }.to have_enqueued_job(Agent::UpdateJob).with(hash_including(force: true))
        end
      end

      context "with HTML format fallback" do
        it "redirects when not accepting turbo_stream" do
          post node_update_path(node), params: { agent_release_id: agent_release.id },
               headers: { "Accept" => "text/html" }
          expect(response).to redirect_to(node_path(node))
        end
      end
    end
  end
end
