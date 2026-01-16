# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }
  let(:node) { create(:node, uuid: "test-node-uuid") }
  let!(:api_key) { create(:api_key, token: "valid_token_123") }

  describe "#connect" do
    context "with authenticated user" do
      it "connects successfully" do
        connect "/cable", env: { "warden" => double(user: user) }
        expect(connection.current_user).to eq(user)
      end
    end

    context "with valid node token via Authorization header" do
      it "connects successfully with node identified by UUID" do
        connect "/cable", headers: {
          "Authorization" => "Bearer valid_token_123",
          "X-Node-ID" => node.uuid
        }
        expect(connection.current_node).to eq(node)
      end
    end

    context "with valid node token via query parameter" do
      it "connects successfully with node identified by UUID" do
        connect "/cable?token=valid_token_123", headers: {
          "X-Node-ID" => node.uuid
        }
        expect(connection.current_node).to eq(node)
      end
    end

    context "without authentication" do
      it "rejects the connection" do
        expect { connect "/cable" }.to have_rejected_connection
      end
    end

    context "with invalid token" do
      it "rejects the connection" do
        expect {
          connect "/cable", headers: {
            "Authorization" => "Bearer invalid_token",
            "X-Node-ID" => node.uuid
          }
        }.to have_rejected_connection
      end
    end

    context "with valid token but no node ID" do
      it "rejects the connection" do
        expect {
          connect "/cable", headers: {
            "Authorization" => "Bearer valid_token_123"
          }
        }.to have_rejected_connection
      end
    end

    context "with valid token but unknown node UUID" do
      it "rejects the connection" do
        expect {
          connect "/cable", headers: {
            "Authorization" => "Bearer valid_token_123",
            "X-Node-ID" => "unknown-uuid"
          }
        }.to have_rejected_connection
      end
    end
  end
end
