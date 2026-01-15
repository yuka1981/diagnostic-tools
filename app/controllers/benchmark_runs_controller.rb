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

    # Prefer stored_path (server-managed storage) over original path
    safe_path = validated_artifact_path(@artifact)
    unless safe_path
      flash[:alert] = "Artifact file not found on server."
      redirect_to benchmark_run_path(@benchmark_run) and return
    end

    send_file safe_path,
              filename: File.basename(safe_path),
              type: mime_type_for(@artifact),
              disposition: "attachment"
  end

  def cancel
    @benchmark_run = BenchmarkRun.find(params[:id])

    unless @benchmark_run.pending? || @benchmark_run.running?
      flash[:alert] = "Cannot cancel a completed benchmark run."
      redirect_to benchmark_run_path(@benchmark_run) and return
    end

    service = Benchmark::CancelRunService.new(@benchmark_run)
    result = service.call

    if result.success?
      flash[:notice] = "Benchmark run cancelled successfully."
    else
      flash[:alert] = "Failed to cancel benchmark run: #{result.error}"
    end

    respond_to do |format|
      format.html { redirect_to benchmark_runs_path }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "benchmark_run_#{@benchmark_run.id}",
          partial: "benchmark_runs/run_row",
          locals: { run: @benchmark_run.reload }
        )
      end
    end
  end

  private

  def filter_params
    params.permit(:status, :node_id, :recipe_id, :q)
  end

  # Validates that an artifact can be served.
  # Prefers stored_path (server-managed storage) over original path.
  # Returns the file path if valid and exists, nil otherwise.
  def validated_artifact_path(artifact)
    # First, try stored_path (uploaded artifacts stored by server)
    if artifact.stored_path.present?
      stored = validate_stored_path(artifact.stored_path)
      return stored if stored
    end

    # Fall back to original path with base_path validation (legacy behavior)
    validate_legacy_path(artifact.path)
  end

  # Validates a stored path (server-managed storage location)
  def validate_stored_path(path)
    return nil if path.blank?

    storage_base = Rails.configuration.x.artifacts_storage_path.presence ||
                   Rails.root.join("storage", "artifacts").to_s

    artifact_path = Pathname.new(path).cleanpath.to_s

    # Verify path is within storage directory and file exists
    return nil unless artifact_path.start_with?(storage_base)
    return nil unless File.file?(artifact_path)

    artifact_path
  end

  # Validates a legacy path (shared filesystem)
  def validate_legacy_path(path)
    return nil if path.blank?

    base_path = Rails.configuration.x.artifacts_base_path
    base_path = "/shared/artifacts" unless base_path.is_a?(String) && base_path.present?

    allowed_base = Pathname.new(base_path).cleanpath.to_s
    artifact_path = Pathname.new(path).cleanpath.to_s

    # Verify path is within allowed directory and file exists
    return nil unless artifact_path.start_with?(allowed_base + File::SEPARATOR) || artifact_path == allowed_base
    return nil unless File.file?(artifact_path)

    artifact_path
  end

  def mime_type_for(artifact)
    case artifact.file_type.to_s.downcase
    when "txt", "log", "dat"
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
