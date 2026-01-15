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

    safe_path = validated_artifact_path(@artifact.path)
    unless safe_path
      flash[:alert] = "Artifact file not found on server."
      redirect_to benchmark_run_path(@benchmark_run) and return
    end

    send_file safe_path,
              filename: File.basename(safe_path),
              type: mime_type_for(@artifact),
              disposition: "attachment"
  end

  private

  def filter_params
    params.permit(:status, :node_id, :recipe_id, :q)
  end

  # Validates that an artifact path is within the allowed artifacts directory.
  # Returns the sanitized absolute path if valid, nil otherwise.
  def validated_artifact_path(path)
    return nil if path.blank?

    base_path = Rails.configuration.x.artifacts_base_path
    base_path = "/shared/artifacts" unless base_path.is_a?(String) && base_path.present?

    # Resolve to absolute paths and remove any path traversal attempts
    allowed_base = Pathname.new(base_path).cleanpath.to_s
    artifact_path = Pathname.new(path).cleanpath.to_s

    # Verify path is within allowed directory and file exists
    return nil unless artifact_path.start_with?(allowed_base + File::SEPARATOR) || artifact_path == allowed_base
    return nil unless File.file?(artifact_path)

    artifact_path
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
