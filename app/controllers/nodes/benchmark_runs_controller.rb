# frozen_string_literal: true

module Nodes
  class BenchmarkRunsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :set_node
    before_action :authorize_approver!

    def new
      @form = Benchmark::RunForm.new
    end

    def create
      @form = Benchmark::RunForm.new(run_params)

      if @form.valid?
        # Ensure recipe exists
        recipe = BenchmarkRecipe.find_or_create_by!(name: "HPCG", version: "3.1")

        # Create run record
        run = @node.benchmark_runs.create!(
          benchmark_recipe: recipe,
          log_path: @form.log_path,
          status: :pending
        )

        trigger_service = Benchmark::TriggerRunService.new(
          @node,
          log_path: @form.log_path,
          run_id: run.uuid,
          server_url: request.base_url,
          agent_token: Rails.application.credentials.dig(:api, :agent_token) || ENV["API_AGENT_TOKEN"]
        )
        result = trigger_service.call

        if result.success?
          redirect_to benchmark_runs_path(node_id: @node.id), notice: "Benchmark triggered successfully."
        else
          run.update!(status: :failed, error_message: result.error)
          flash.now[:alert] = "Failed to trigger benchmark: #{result.error}"
          render :new, status: :unprocessable_entity
        end
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def set_node
      @node = Node.find(params[:node_id])
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to node_path(@node), alert: "You are not authorized to run benchmarks."
    end

    def run_params
      params.require(:benchmark_run_form).permit(:log_path)
    end
  end
end
