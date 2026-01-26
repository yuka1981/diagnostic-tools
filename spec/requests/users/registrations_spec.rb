# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::Registrations", type: :request do
  describe "GET /users/sign_up" do
    it "renders the registration page" do
      get new_user_registration_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign Up")
    end
  end

  describe "POST /users" do
    context "with valid parameters" do
      let(:valid_params) do
        {
          user: {
            name: "Test User",
            email: "newuser#{SecureRandom.hex(4)}@example.com",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end

      it "creates a new user" do
        expect {
          post user_registration_path, params: valid_params
        }.to change(User, :count).by(1)
      end

      it "redirects to root after sign up" do
        post user_registration_path, params: valid_params
        expect(response).to redirect_to(root_path)
      end

      it "assigns default viewer role" do
        post user_registration_path, params: valid_params
        expect(User.last.role).to eq("viewer")
      end
    end

    context "with invalid parameters" do
      it "does not create user with blank email" do
        expect {
          post user_registration_path, params: {
            user: {
              name: "Test User",
              email: "",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not create user with mismatched passwords" do
        expect {
          post user_registration_path, params: {
            user: {
              name: "Test User",
              email: "test@example.com",
              password: "password123",
              password_confirmation: "differentpassword"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not create user with blank name" do
        expect {
          post user_registration_path, params: {
            user: {
              name: "",
              email: "test@example.com",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not create user with duplicate email" do
        create(:user, email: "existing@example.com")

        expect {
          post user_registration_path, params: {
            user: {
              name: "Test User",
              email: "existing@example.com",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
