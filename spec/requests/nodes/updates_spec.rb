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

      context "when node is busy" do
        before do
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending)
        end

        it "redirects with busy error message" do
          post node_update_path(node), params: { agent_release_id: agent_release.id }
          expect(response).to redirect_to(node_path(node))
          follow_redirect!
          expect(response.body).to include("currently busy")
        end

        it "allows update when force is true (but fails at SSH)" do
          post node_update_path(node), params: { agent_release_id: agent_release.id, force: "true" }
          expect(response).to redirect_to(node_path(node))
          follow_redirect!
          # Should fail at SSH level, not busy check
          expect(response.body).to include("failed")
        end
      end

      context "when node is idle" do
        before do
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :success)
        end

        it "attempts update (fails at SSH in test environment)" do
          post node_update_path(node), params: { agent_release_id: agent_release.id }
          expect(response).to redirect_to(node_path(node))
          follow_redirect!
          # Will fail at SSH connection in test environment
          expect(response.body).to include("failed")
        end
      end
    end
  end
end
