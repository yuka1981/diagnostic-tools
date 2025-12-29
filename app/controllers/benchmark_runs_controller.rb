# frozen_string_literal: true

class BenchmarkRunsController < ApplicationController
  layout "dashboard"
  helper_method :filter_params

  def index
    @filter = Runs::FilterQuery.new(filter_params)
    @benchmark_runs = @filter.call.page(params[:page]).per(20)

    # Load data for filter dropdowns
    @nodes = Node.order(:hostname)
    @recipes = BenchmarkRecipe.order(:name)
  end

  def show
    @benchmark_run = BenchmarkRun.find(params[:id])

    # Respond with slide-over content for Turbo Frame requests, otherwise render show.html.erb
    return unless turbo_frame_request_id == "slide_over_content"

    render partial: "benchmark_runs/slide_over_content",
           locals: { benchmark_run: @benchmark_run },
           layout: false
  end

  private

  def filter_params
    params.permit(:status, :node_id, :recipe_id, :q)
  end
end
