# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BenchmarkRecipes", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user, :viewer) }

  describe "GET /benchmark_recipes" do
    let!(:recipe) { create(:benchmark_recipe, :hpcg) }

    context "when authenticated" do
      before { sign_in viewer }

      it "returns http success" do
        get benchmark_recipes_path
        expect(response).to have_http_status(:success)
      end

      it "displays the recipes" do
        get benchmark_recipes_path
        expect(response.body).to include(recipe.name)
      end
    end

    context "when not authenticated" do
      it "redirects to login" do
        get benchmark_recipes_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /benchmark_recipes/:id" do
    let!(:recipe) { create(:benchmark_recipe, :hpcg) }

    context "when authenticated" do
      before { sign_in viewer }

      it "returns http success" do
        get benchmark_recipe_path(recipe)
        expect(response).to have_http_status(:success)
      end

      it "displays the recipe details" do
        get benchmark_recipe_path(recipe)
        expect(response.body).to include(recipe.name)
        expect(response.body).to include(recipe.command)
      end
    end
  end

  describe "GET /benchmark_recipes/new" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns http success" do
        get new_benchmark_recipe_path
        expect(response).to have_http_status(:success)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        get new_benchmark_recipe_path
        expect(response).to redirect_to(benchmark_recipes_path)
      end
    end
  end

  describe "POST /benchmark_recipes" do
    let(:valid_params) do
      {
        benchmark_recipe: {
          name: "Stream",
          version: "1.0",
          command: "stream",
          description: "Memory bandwidth benchmark",
          timeout_seconds: 1800
        }
      }
    end

    let(:invalid_params) do
      {
        benchmark_recipe: {
          name: "",
          version: "",
          command: ""
        }
      }
    end

    context "when authenticated as approver" do
      before { sign_in approver }

      it "creates a new benchmark recipe with valid params" do
        expect {
          post benchmark_recipes_path, params: valid_params
        }.to change(BenchmarkRecipe, :count).by(1)
      end

      it "redirects to the recipe after creation" do
        post benchmark_recipes_path, params: valid_params
        expect(response).to redirect_to(benchmark_recipe_path(BenchmarkRecipe.last))
      end

      it "auto-generates slug if not provided" do
        post benchmark_recipes_path, params: valid_params
        expect(BenchmarkRecipe.last.slug).to eq("stream-1-0")
      end

      it "does not create with invalid params" do
        expect {
          post benchmark_recipes_path, params: invalid_params
        }.not_to change(BenchmarkRecipe, :count)
      end

      it "renders new on validation error" do
        post benchmark_recipes_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        post benchmark_recipes_path, params: valid_params
        expect(response).to redirect_to(benchmark_recipes_path)
      end
    end
  end

  describe "GET /benchmark_recipes/:id/edit" do
    let!(:recipe) { create(:benchmark_recipe, :hpcg) }

    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns http success" do
        get edit_benchmark_recipe_path(recipe)
        expect(response).to have_http_status(:success)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        get edit_benchmark_recipe_path(recipe)
        expect(response).to redirect_to(benchmark_recipes_path)
      end
    end
  end

  describe "PATCH /benchmark_recipes/:id" do
    let!(:recipe) { create(:benchmark_recipe, :hpcg) }

    context "when authenticated as approver" do
      before { sign_in approver }

      it "updates the recipe" do
        patch benchmark_recipe_path(recipe), params: {
          benchmark_recipe: { description: "Updated description" }
        }
        expect(recipe.reload.description).to eq("Updated description")
      end

      it "redirects to the recipe" do
        patch benchmark_recipe_path(recipe), params: {
          benchmark_recipe: { description: "Updated" }
        }
        expect(response).to redirect_to(benchmark_recipe_path(recipe))
      end

      it "renders edit on validation error" do
        patch benchmark_recipe_path(recipe), params: {
          benchmark_recipe: { name: "" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        patch benchmark_recipe_path(recipe), params: {
          benchmark_recipe: { description: "Hacked" }
        }
        expect(response).to redirect_to(benchmark_recipes_path)
      end
    end
  end

  describe "DELETE /benchmark_recipes/:id" do
    let!(:recipe) { create(:benchmark_recipe, :hpcg) }

    context "when authenticated as approver" do
      before { sign_in approver }

      context "when recipe has no runs" do
        it "deletes the recipe" do
          expect {
            delete benchmark_recipe_path(recipe)
          }.to change(BenchmarkRecipe, :count).by(-1)
        end

        it "redirects to index" do
          delete benchmark_recipe_path(recipe)
          expect(response).to redirect_to(benchmark_recipes_path)
        end
      end

      context "when recipe has associated runs" do
        let!(:node) { create(:node) }
        let!(:run) { create(:benchmark_run, benchmark_recipe: recipe, node: node) }

        it "does not delete the recipe" do
          expect {
            delete benchmark_recipe_path(recipe)
          }.not_to change(BenchmarkRecipe, :count)
        end

        it "shows error message" do
          delete benchmark_recipe_path(recipe)
          expect(flash[:alert]).to be_present
        end
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects with unauthorized message" do
        delete benchmark_recipe_path(recipe)
        expect(response).to redirect_to(benchmark_recipes_path)
      end
    end
  end

  describe "PATCH /benchmark_recipes/:id/archive" do
    let!(:recipe) { create(:benchmark_recipe, :hpcg, status: :active) }

    context "when authenticated as approver" do
      before { sign_in approver }

      it "archives the recipe" do
        patch archive_benchmark_recipe_path(recipe)
        expect(recipe.reload).to be_archived
      end

      it "redirects to the recipe" do
        patch archive_benchmark_recipe_path(recipe)
        expect(response).to redirect_to(benchmark_recipe_path(recipe))
      end
    end
  end

  describe "PATCH /benchmark_recipes/:id/activate" do
    let!(:recipe) { create(:benchmark_recipe, :hpcg, :archived) }

    context "when authenticated as approver" do
      before { sign_in approver }

      it "activates the recipe" do
        patch activate_benchmark_recipe_path(recipe)
        expect(recipe.reload).to be_active
      end
    end
  end
end
