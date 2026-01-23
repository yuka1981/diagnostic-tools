# frozen_string_literal: true

class TasksController < ApplicationController
  layout "dashboard"
  helper_method :filter_params

  PER_PAGE_OPTIONS = [ 10, 20, 50 ].freeze
  DEFAULT_PER_PAGE = 20

  def index
    @filter = Tasks::FilterQuery.new(filter_params)
    all_tasks = @filter.call
    @per_page = validated_per_page
    @tasks = Kaminari.paginate_array(all_tasks).page(params[:page]).per(@per_page)

    # Load data for filter dropdowns
    @nodes = Node.order(:hostname)
    @benchmark_recipes = BenchmarkRecipe.active.order(:name)
    @profiling_recipes = ProfilingRecipe.active.order(:name)
  end

  def cancel
    run = find_run
    return redirect_with_error("Task not found") unless run

    unless run.pending? || run.running?
      return redirect_with_error("Cannot cancel a completed task")
    end

    if run.is_a?(BenchmarkRun)
      service = Benchmark::CancelRunService.new(run)
      result = service.call
      message = result.success? ? "Task cancelled successfully" : "Failed to cancel: #{result.error}"
    else
      run.update!(status: :cancelled, error_message: "Cancelled by user at #{Time.current}")
      message = "Task cancelled successfully"
    end

    respond_to do |format|
      format.html { redirect_to tasks_path, notice: message }
      format.turbo_stream { redirect_to tasks_path, notice: message }
    end
  end

  def destroy
    run = find_run
    return redirect_with_error("Task not found") unless run

    run.destroy!
    redirect_to tasks_path, notice: "Task deleted successfully"
  end

  def rerun
    run = find_run
    return redirect_with_error("Task not found") unless run

    if run.is_a?(BenchmarkRun)
      new_run = BenchmarkRun.create!(
        node: run.node,
        benchmark_recipe: run.benchmark_recipe,
        arguments: run.arguments,
        log_path: run.log_path
      )
      Benchmark::TriggerJob.perform_later(
        new_run.node,
        new_run,
        request.base_url,
        agent_token(new_run.node),
        {},
        user_id: current_user.id
      )
    else
      new_run = ProfilingRun.create!(
        node: run.node,
        profiling_recipe: run.profiling_recipe,
        subcommand: run.subcommand,
        options: run.options,
        user: current_user
      )
      Profiling::TriggerJob.perform_later(
        new_run,
        request.base_url,
        agent_token(new_run.node),
        user_id: current_user.id
      )
    end

    redirect_to tasks_path, notice: "Task re-triggered successfully"
  end

  private

  def filter_params
    params.permit(:type, :status, :node_id, :recipe_id, :date_range, :q, :per_page)
  end

  def validated_per_page
    per_page = params[:per_page].to_i
    PER_PAGE_OPTIONS.include?(per_page) ? per_page : DEFAULT_PER_PAGE
  end

  def find_run
    parsed = Task.parse_param(params[:id])
    return nil unless parsed

    type, id = parsed
    type == :benchmark ? BenchmarkRun.find_by(id: id) : ProfilingRun.find_by(id: id)
  end

  def redirect_with_error(message)
    redirect_to tasks_path, alert: message
  end

  def agent_token(node)
    node.effective_api_token.presence ||
      Rails.application.credentials.dig(:api, :agent_token) ||
      ENV["API_AGENT_TOKEN"]
  end
end
