# frozen_string_literal: true

class BenchmarkRunsController < ApplicationController
  layout "dashboard"

  def index
    @benchmark_runs = BenchmarkRun.recent.includes(:node, :benchmark_recipe)
  end

  def show
    @benchmark_run = BenchmarkRun.find(params[:id])

    # Respond with slide-over content for Turbo Frame requests
    if turbo_frame_request_id == "slide_over_content"
      render partial: "benchmark_runs/slide_over_content",
             locals: { benchmark_run: @benchmark_run },
             layout: false
    end
    # Otherwise render regular show.html.erb
  end
end
