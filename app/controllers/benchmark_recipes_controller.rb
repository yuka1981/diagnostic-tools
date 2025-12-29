# frozen_string_literal: true

class BenchmarkRecipesController < ApplicationController
  layout "dashboard"

  def index
    @benchmark_recipes = BenchmarkRecipe.order(:name, :version)
  end

  def show
    @benchmark_recipe = BenchmarkRecipe.find(params[:id])
  end
end
