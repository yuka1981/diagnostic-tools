# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Nodes", type: :request do
  describe "GET /api/nodes/hostname_suggestions" do
    describe "single hostname prefix" do
      context "when there are existing hostnames matching the prefix" do
        before do
          create(:node, hostname: "compute-001")
          create(:node, hostname: "compute-002")
          create(:node, hostname: "compute-005")
          create(:node, hostname: "storage-001")
        end

        it "returns existing hostnames matching the prefix" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "compute" }

          expect(response).to have_http_status(:success)
          json = response.parsed_body
          expect(json["existing"]).to contain_exactly("compute-001", "compute-002", "compute-005")
        end

        it "returns suggested next hostnames filling gaps" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "compute" }

          json = response.parsed_body
          # Should suggest compute-003, compute-004 (gaps) and compute-006 (next)
          expect(json["suggestions"]).to include("compute-003", "compute-004", "compute-006")
        end

        it "does not return non-matching hostnames in existing" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "compute" }

          json = response.parsed_body
          expect(json["existing"]).not_to include("storage-001")
        end
      end

      context "when prefix exactly matches a single hostname" do
        before do
          create(:node, hostname: "login-node")
          create(:node, hostname: "login-node-01")
        end

        it "returns the exact match" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "login-node" }

          json = response.parsed_body
          expect(json["existing"]).to include("login-node", "login-node-01")
        end
      end

      context "when there are no matching hostnames" do
        before do
          create(:node, hostname: "compute-001")
        end

        it "returns empty arrays" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "storage" }

          expect(response).to have_http_status(:success)
          json = response.parsed_body
          expect(json["existing"]).to be_empty
          expect(json["suggestions"]).to be_empty
        end
      end

      context "when prefix is empty" do
        before do
          create(:node, hostname: "compute-001")
        end

        it "returns empty results" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "" }

          json = response.parsed_body
          expect(json["existing"]).to be_empty
          expect(json["suggestions"]).to be_empty
        end
      end

      context "with SQL LIKE special characters in prefix" do
        before do
          create(:node, hostname: "node_test-001")
          create(:node, hostname: "nodeXtest-001")
        end

        it "escapes underscore wildcard" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "node_test" }

          json = response.parsed_body
          expect(json["existing"]).to contain_exactly("node_test-001")
          expect(json["existing"]).not_to include("nodeXtest-001")
        end
      end
    end

    describe "bulk pattern with range notation" do
      context "when pattern contains [N-M] range" do
        before do
          create(:node, hostname: "compute-002")
          create(:node, hostname: "compute-004")
        end

        it "detects bulk pattern and returns expanded hostnames" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "compute-[001-005]" }

          expect(response).to have_http_status(:success)
          json = response.parsed_body
          expect(json["bulk"]).to be true
          expect(json["hostnames"]).to contain_exactly(
            "compute-001", "compute-002", "compute-003", "compute-004", "compute-005"
          )
        end

        it "returns conflicts with existing hostnames" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "compute-[001-005]" }

          json = response.parsed_body
          expect(json["conflicts"]).to contain_exactly("compute-002", "compute-004")
        end

        it "returns available hostnames (non-conflicting)" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "compute-[001-005]" }

          json = response.parsed_body
          expect(json["available"]).to contain_exactly("compute-001", "compute-003", "compute-005")
        end
      end

      context "when bulk range has no conflicts" do
        it "returns empty conflicts array" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "newnode-[001-003]" }

          json = response.parsed_body
          expect(json["bulk"]).to be true
          expect(json["conflicts"]).to be_empty
          expect(json["available"]).to contain_exactly("newnode-001", "newnode-002", "newnode-003")
        end
      end

      context "with different padding formats" do
        before do
          create(:node, hostname: "gpu-01")
        end

        it "respects the padding width in the pattern" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "gpu-[01-03]" }

          json = response.parsed_body
          expect(json["hostnames"]).to contain_exactly("gpu-01", "gpu-02", "gpu-03")
          expect(json["conflicts"]).to contain_exactly("gpu-01")
        end
      end

      context "with invalid range (start > end)" do
        it "returns empty hostnames" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "node-[005-001]" }

          json = response.parsed_body
          expect(json["bulk"]).to be true
          expect(json["hostnames"]).to be_empty
        end
      end

      context "with very large range" do
        it "limits the number of expanded hostnames" do
          get hostname_suggestions_api_nodes_path, params: { prefix: "node-[0001-9999]" }

          json = response.parsed_body
          expect(json["hostnames"].size).to be <= 100
        end
      end
    end

    describe "response format" do
      it "returns JSON content type" do
        get hostname_suggestions_api_nodes_path, params: { prefix: "test" }

        expect(response.content_type).to include("application/json")
      end
    end
  end
end
