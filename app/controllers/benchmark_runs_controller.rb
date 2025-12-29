# frozen_string_literal: true

class BenchmarkRunsController < ApplicationController
  layout "dashboard"

  def index
    @benchmark_runs = BenchmarkRun.recent.includes(:node, :benchmark_recipe)
  end

  def show
    @benchmark_run = BenchmarkRun.find(params[:id])
  end
end
