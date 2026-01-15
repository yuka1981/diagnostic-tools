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

  def download_artifact
    @benchmark_run = BenchmarkRun.find(params[:id])
    @artifact = @benchmark_run.artifact_indices.find(params[:artifact_id])

    # Security check: ensure file exists and is within allowed paths
    unless File.exist?(@artifact.path)
      flash[:alert] = "Artifact file not found on server."
      redirect_to benchmark_run_path(@benchmark_run) and return
    end

    # Send the file for download
    send_file @artifact.path,
              filename: File.basename(@artifact.path),
              type: mime_type_for(@artifact),
              disposition: "attachment"
  end

  private

  def filter_params
    params.permit(:status, :node_id, :recipe_id, :q)
  end

  def mime_type_for(artifact)
    case artifact.file_type.to_s.downcase
    when "txt", "log"
      "text/plain"
    when "yaml", "yml"
      "text/yaml"
    when "json"
      "application/json"
    when "csv"
      "text/csv"
    when "pdf"
      "application/pdf"
    when "tar", "gz", "tgz"
      "application/gzip"
    when "zip"
      "application/zip"
    else
      "application/octet-stream"
    end
  end
end
