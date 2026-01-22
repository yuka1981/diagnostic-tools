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

  describe "POST /api/nodes/validate" do
    describe "hostname uniqueness" do
      context "when hostname does not exist" do
        it "returns valid: true" do
          post validate_api_nodes_path, params: { node: { hostname: "new-node" } }, as: :json

          expect(response).to have_http_status(:success)
          json = response.parsed_body
          expect(json["valid"]).to be true
          expect(json["errors"]).to be_empty
        end
      end

      context "when hostname already exists" do
        before do
          create(:node, hostname: "existing-node")
        end

        it "returns valid: false with hostname error" do
          post validate_api_nodes_path, params: { node: { hostname: "existing-node" } }, as: :json

          expect(response).to have_http_status(:success)
          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["hostname"]).to include("has already been taken")
        end
      end

      context "when editing an existing node" do
        let!(:node) { create(:node, hostname: "my-node") }

        it "excludes self from uniqueness check" do
          post validate_api_nodes_path, params: { node: { id: node.id, hostname: "my-node" } }, as: :json

          expect(response).to have_http_status(:success)
          json = response.parsed_body
          expect(json["valid"]).to be true
          expect(json["errors"]).to be_empty
        end

        it "still validates against other nodes" do
          create(:node, hostname: "other-node")

          post validate_api_nodes_path, params: { node: { id: node.id, hostname: "other-node" } }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["hostname"]).to include("has already been taken")
        end
      end

      context "when id is provided but node does not exist" do
        it "returns valid: false with node not found error" do
          post validate_api_nodes_path, params: { node: { id: 999999, hostname: "new-node" } }, as: :json

          expect(response).to have_http_status(:success)
          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["base"]).to include("Node not found")
        end
      end

      context "when hostname is localhost" do
        it "returns valid: false with hostname error" do
          post validate_api_nodes_path, params: { node: { hostname: "localhost" } }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["hostname"]).to include("cannot be localhost. Please use a remote hostname or IP address.")
        end
      end
    end

    describe "rack position overlap" do
      let!(:rack) { create(:server_rack, u_height: 42) }

      context "when rack position does not overlap" do
        before do
          create(:node, :racked, server_rack: rack, rack_position: 1, rack_height: 2)
        end

        it "returns valid: true" do
          post validate_api_nodes_path, params: {
            node: { hostname: "new-node", rack_id: rack.id, rack_position: 5, rack_height: 2 }
          }, as: :json

          expect(response).to have_http_status(:success)
          json = response.parsed_body
          expect(json["valid"]).to be true
          expect(json["errors"]).to be_empty
        end
      end

      context "when rack position overlaps with existing node" do
        let!(:existing_node) { create(:node, hostname: "existing-racked", server_rack: rack, rack_position: 10, rack_height: 2) }

        it "returns valid: false with base error" do
          post validate_api_nodes_path, params: {
            node: { hostname: "new-node", rack_id: rack.id, rack_position: 11, rack_height: 2 }
          }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["base"]).to include("Position overlaps with existing node existing-racked")
        end

        it "detects overlap when new node starts before existing" do
          post validate_api_nodes_path, params: {
            node: { hostname: "new-node", rack_id: rack.id, rack_position: 9, rack_height: 2 }
          }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["base"]).to include("Position overlaps with existing node existing-racked")
        end

        it "detects overlap when new node completely contains existing" do
          post validate_api_nodes_path, params: {
            node: { hostname: "new-node", rack_id: rack.id, rack_position: 9, rack_height: 4 }
          }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["base"]).to include("Position overlaps with existing node existing-racked")
        end
      end

      context "when editing an existing racked node" do
        let!(:node) { create(:node, hostname: "my-racked-node", server_rack: rack, rack_position: 10, rack_height: 2) }

        it "excludes self from overlap check" do
          post validate_api_nodes_path, params: {
            node: { id: node.id, hostname: "my-racked-node", rack_id: rack.id, rack_position: 10, rack_height: 2 }
          }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be true
          expect(json["errors"]).to be_empty
        end

        it "allows moving position when not overlapping with others" do
          post validate_api_nodes_path, params: {
            node: { id: node.id, hostname: "my-racked-node", rack_id: rack.id, rack_position: 15, rack_height: 2 }
          }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be true
        end

        it "detects overlap with other nodes when moving" do
          create(:node, hostname: "other-racked", server_rack: rack, rack_position: 20, rack_height: 2)

          post validate_api_nodes_path, params: {
            node: { id: node.id, hostname: "my-racked-node", rack_id: rack.id, rack_position: 20, rack_height: 2 }
          }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["base"]).to include("Position overlaps with existing node other-racked")
        end
      end

      context "when rack position exceeds rack height" do
        it "returns valid: false with rack_position error" do
          post validate_api_nodes_path, params: {
            node: { hostname: "new-node", rack_id: rack.id, rack_position: 50, rack_height: 1 }
          }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["rack_position"]).to include("must be less than or equal to 42")
        end
      end

      context "when node extends beyond rack height" do
        it "returns valid: false with base error" do
          post validate_api_nodes_path, params: {
            node: { hostname: "new-node", rack_id: rack.id, rack_position: 41, rack_height: 4 }
          }, as: :json

          json = response.parsed_body
          expect(json["valid"]).to be false
          expect(json["errors"]["base"].first).to include("extends beyond rack height")
        end
      end
    end

    describe "combined validations" do
      let!(:rack) { create(:server_rack, u_height: 42) }

      before do
        create(:node, hostname: "existing-node")
        create(:node, hostname: "existing-racked", server_rack: rack, rack_position: 10, rack_height: 2)
      end

      it "returns multiple errors when both hostname and position are invalid" do
        post validate_api_nodes_path, params: {
          node: { hostname: "existing-node", rack_id: rack.id, rack_position: 10, rack_height: 2 }
        }, as: :json

        json = response.parsed_body
        expect(json["valid"]).to be false
        expect(json["errors"]["hostname"]).to include("has already been taken")
        expect(json["errors"]["base"]).to include("Position overlaps with existing node existing-racked")
      end
    end

    describe "response format" do
      it "returns JSON content type" do
        post validate_api_nodes_path, params: { node: { hostname: "test" } }, as: :json

        expect(response.content_type).to include("application/json")
      end
    end
  end
end
