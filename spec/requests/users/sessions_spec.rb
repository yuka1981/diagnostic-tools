# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::Sessions", type: :request do
  let(:user) { create(:user, password: "password123") }

  describe "GET /users/sign_in" do
    it "renders the sign in page" do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in")
    end
  end

  describe "POST /users/sign_in" do
    context "with valid credentials" do
      it "signs in the user and redirects to root" do
        post user_session_path, params: {
          user: {
            email: user.email,
            password: "password123"
          }
        }
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Signed in successfully")
      end
    end

    context "with invalid credentials" do
      it "does not sign in and shows error" do
        post user_session_path, params: {
          user: {
            email: user.email,
            password: "wrongpassword"
          }
        }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Invalid Email or password")
      end
    end

    context "with non-existent user" do
      it "does not sign in and shows error" do
        post user_session_path, params: {
          user: {
            email: "nonexistent@example.com",
            password: "password123"
          }
        }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Invalid Email or password")
      end
    end
  end

  describe "DELETE /users/sign_out" do
    before do
      sign_in user
    end

    it "signs out the user and redirects to root" do
      delete destroy_user_session_path
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include("Signed out successfully")
    end
  end
end
