# frozen_string_literal: true

class MlcBenchmarksController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :authorize_approver!

  def new
    @form = Mlc::RunForm.new(profile: "quick")
    @nodes = Node.order(:hostname)
  end

  def create
    @form = Mlc::RunForm.new(form_params)

    if @form.valid?
      recipe = BenchmarkRecipe.find_by!(slug: "mlc")
      argument_overrides = @form.argument_overrides_hash

      argument_builder = Benchmark::ArgumentBuilderService.new(
        defaults: recipe.default_profile,
        overrides: argument_overrides
      )

      run = @form.node.benchmark_runs.create!(
        benchmark_recipe: recipe,
        log_path: @form.log_path,
        arguments: argument_builder.merged_arguments,
        status: :pending
      )

      Benchmark::TriggerJob.perform_later(
        @form.node,
        run,
        argument_overrides,
        user_id: current_user.id
      )

      redirect_to node_path(@form.node), notice: "MLC benchmark triggered successfully."
    else
      @nodes = Node.order(:hostname)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def authorize_approver!
    return if current_user.approver?

    redirect_to root_path, alert: "You are not authorized to run benchmarks."
  end

  def form_params
    params.require(:mlc_run_form).permit(:node_id, :profile, :binary_path, :modules, :log_path)
  end
end
