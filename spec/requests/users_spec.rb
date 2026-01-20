# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users", type: :request do
  describe "PATCH /users/preferences" do
    context "when authenticated" do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      context "with valid fields" do
        let(:valid_params) do
          {
            rack_node_preview_fields: %w[cpu ram storage]
          }
        end

        it "updates the user's rack_node_preview_fields" do
          patch users_preferences_path, params: valid_params

          expect(user.reload.rack_node_preview_fields).to eq(%w[cpu ram storage])
        end

        it "returns success status" do
          patch users_preferences_path, params: valid_params

          expect(response).to have_http_status(:ok)
        end

        it "returns JSON with success message" do
          patch users_preferences_path, params: valid_params, as: :json

          expect(response.content_type).to include("application/json")
          json_response = JSON.parse(response.body)
          expect(json_response["success"]).to be true
        end

        it "accepts empty array to clear fields" do
          user.update!(rack_node_preview_fields: %w[cpu ram])

          patch users_preferences_path, params: { rack_node_preview_fields: [] }

          expect(user.reload.rack_node_preview_fields).to eq([])
        end

        it "accepts all valid fields" do
          all_fields = User::VALID_RACK_NODE_PREVIEW_FIELDS
          patch users_preferences_path, params: { rack_node_preview_fields: all_fields }

          expect(user.reload.rack_node_preview_fields).to eq(all_fields)
        end
      end

      context "with invalid fields" do
        let(:invalid_params) do
          {
            rack_node_preview_fields: %w[cpu invalid_field]
          }
        end

        it "does not update the user's preferences" do
          original_fields = user.rack_node_preview_fields

          patch users_preferences_path, params: invalid_params

          expect(user.reload.rack_node_preview_fields).to eq(original_fields)
        end

        it "returns unprocessable_entity status" do
          patch users_preferences_path, params: invalid_params

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "returns JSON with error message" do
          patch users_preferences_path, params: invalid_params, as: :json

          expect(response.content_type).to include("application/json")
          json_response = JSON.parse(response.body)
          expect(json_response["success"]).to be false
          expect(json_response["errors"]).to include("Rack node preview fields contains invalid fields: invalid_field")
        end
      end

      context "with turbo stream request" do
        let(:valid_params) do
          {
            rack_node_preview_fields: %w[cpu ram]
          }
        end

        it "returns turbo stream response when accepted" do
          patch users_preferences_path, params: valid_params, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        end
      end
    end

    context "when not authenticated" do
      it "redirects to sign in page" do
        patch users_preferences_path, params: { rack_node_preview_fields: %w[cpu] }

        expect(response).to redirect_to(new_user_session_path)
      end

      it "returns unauthorized for JSON requests" do
        patch users_preferences_path, params: { rack_node_preview_fields: %w[cpu] }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
