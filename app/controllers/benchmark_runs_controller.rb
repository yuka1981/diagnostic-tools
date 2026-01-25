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

    safe_path = @artifact.safe_download_path
    unless safe_path
      flash[:alert] = "Artifact file not found on server."
      redirect_to benchmark_run_path(@benchmark_run) and return
    end

    send_file safe_path,
              filename: @artifact.filename,
              type: @artifact.mime_type,
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
      format.html { redirect_back(fallback_location: benchmark_runs_path) }
      format.turbo_stream do
        @benchmark_run.reload
        render turbo_stream: [
          # Update the row in the list
          turbo_stream.replace(
            "benchmark_run_#{@benchmark_run.id}",
            partial: "benchmark_runs/run_row",
            locals: { run: @benchmark_run }
          ),
          # Update the slide-over modal content (if open)
          turbo_stream.replace(
            "slide_over_content",
            partial: "benchmark_runs/slide_over_content",
            locals: { benchmark_run: @benchmark_run }
          )
        ]
      end
    end
  end

  private

  def filter_params
    params.permit(:status, :node_id, :recipe_id, :q)
  end
end
