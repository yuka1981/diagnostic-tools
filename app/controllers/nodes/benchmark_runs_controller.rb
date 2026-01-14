# frozen_string_literal: true

module Nodes
  class BenchmarkRunsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :set_node
    before_action :authorize_approver!

    def new
      @form = Benchmark::RunForm.new
      @preflight = Benchmark::PreflightService.new(
        @node,
        server_url: request.base_url,
        agent_token: agent_token
      ).call
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

        Benchmark::TriggerJob.perform_later(
          @node,
          run,
          request.base_url,
          agent_token
        )

        redirect_to node_path(@node), notice: "Benchmark triggered successfully."
      else
        # Re-run preflight checks for re-rendering the form
        @preflight = Benchmark::PreflightService.new(
          @node,
          server_url: request.base_url,
          agent_token: agent_token
        ).call
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

    def agent_token
      # Prefer per-node token, fall back to global token
      @node.api_token.presence || Rails.application.credentials.dig(:api, :agent_token) || ENV["API_AGENT_TOKEN"]
    end
  end
end
