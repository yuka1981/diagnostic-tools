# frozen_string_literal: true

class BenchmarkRecipesController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_benchmark_recipe, only: %i[show edit update destroy archive activate]
  before_action :authorize_approver!, only: %i[new create edit update destroy archive activate]

  def index
    @benchmark_recipes = BenchmarkRecipe.order(:name, :version)
  end

  def show
  end

  def new
    @benchmark_recipe = BenchmarkRecipe.new
  end

  def create
    @benchmark_recipe = BenchmarkRecipe.new(benchmark_recipe_params)

    if @benchmark_recipe.save
      redirect_to @benchmark_recipe, notice: "Benchmark recipe was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @benchmark_recipe.update(benchmark_recipe_params)
      redirect_to @benchmark_recipe, notice: "Benchmark recipe was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @benchmark_recipe.destroy
      redirect_to benchmark_recipes_path, notice: "Benchmark recipe was successfully deleted."
    else
      redirect_to benchmark_recipes_path, alert: "Cannot delete recipe: #{@benchmark_recipe.errors.full_messages.join(', ')}"
    end
  end

  def archive
    @benchmark_recipe.archived!
    redirect_to @benchmark_recipe, notice: "Benchmark recipe was archived."
  end

  def activate
    @benchmark_recipe.active!
    redirect_to @benchmark_recipe, notice: "Benchmark recipe was activated."
  end

  private

  def set_benchmark_recipe
    @benchmark_recipe = BenchmarkRecipe.find(params[:id])
  end

  def benchmark_recipe_params
    params.require(:benchmark_recipe).permit(
      :name, :version, :slug, :command, :description,
      :timeout_seconds, :status, :default_profile
    )
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to benchmark_recipes_path, alert: "You are not authorized to manage benchmark recipes."
  end
end
