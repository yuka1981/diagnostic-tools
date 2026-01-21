# frozen_string_literal: true

module Nodes
  class BenchmarkRunsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :set_node
    before_action :authorize_approver!, only: %i[new create]

    def index
      @benchmark_runs = @node.benchmark_runs
                             .includes(:benchmark_recipe)
                             .order(created_at: :desc)
                             .page(params[:page])
                             .per(20)
    end

    def new
      @form = Benchmark::RunForm.new
      @benchmark_recipes = BenchmarkRecipe.active.order(:name, :version)
      @preflight = Benchmark::PreflightService.new(
        @node,
        server_url: request.base_url,
        agent_token: agent_token
      ).call
    end

    def create
      @form = Benchmark::RunForm.new(run_params)

      if @form.valid?
        recipe = @form.benchmark_recipe
        argument_overrides = @form.argument_overrides_hash

        # Build merged arguments snapshot using ArgumentBuilderService
        argument_builder = Benchmark::ArgumentBuilderService.new(
          defaults: recipe.default_profile,
          overrides: argument_overrides
        )

        # Create run record with arguments snapshot
        run = @node.benchmark_runs.create!(
          benchmark_recipe: recipe,
          log_path: @form.log_path,
          arguments: argument_builder.merged_arguments,
          status: :pending
        )

        Benchmark::TriggerJob.perform_later(
          @node,
          run,
          request.base_url,
          agent_token,
          argument_overrides,
          user_id: current_user.id
        )

        redirect_to node_path(@node), notice: "Benchmark triggered successfully."
      else
        # Re-run preflight checks for re-rendering the form
        @benchmark_recipes = BenchmarkRecipe.active.order(:name, :version)
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
      params.require(:benchmark_run_form).permit(:benchmark_recipe_id, :argument_overrides, :log_path)
    end

    def agent_token
      # Prefer per-node token (from direct column or associated ApiKey), fall back to global token
      @node.effective_api_token.presence ||
        Rails.application.credentials.dig(:api, :agent_token) ||
        ENV["API_AGENT_TOKEN"]
    end
  end
end
