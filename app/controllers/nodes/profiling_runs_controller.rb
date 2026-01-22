# frozen_string_literal: true

module Nodes
  class ProfilingRunsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :set_node
    before_action :authorize_approver!, only: %i[new create]

    def index
      @profiling_runs = @node.profiling_runs
                              .includes(:profiling_recipe, :profiling_artifacts)
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(20)
    end

    def show
      @run = @node.profiling_runs.find(params[:id])
    end

    def download_artifact
      @run = @node.profiling_runs.find(params[:id])
      artifact = @run.profiling_artifacts.find(params[:artifact_id])

      if artifact.downloadable?
        send_file artifact.file_path,
                  filename: artifact.filename,
                  type: artifact.content_type,
                  disposition: "attachment"
      else
        redirect_to node_profiling_run_path(@node, @run), alert: "Artifact not available for download."
      end
    end

    def new
      @form = Profiling::RunForm.new
      @profiling_recipes = ProfilingRecipe.active.order(:name)
    end

    def create
      run_params = profiling_run_params

      run = @node.profiling_runs.create!(
        subcommand: run_params[:subcommand],
        options: run_params[:options] || {},
        profiling_recipe_id: run_params[:profiling_recipe_id],
        user: current_user,
        status: :pending
      )

      Profiling::TriggerJob.perform_later(
        run,
        request.base_url,
        agent_token,
        user_id: current_user.id
      )

      redirect_to node_path(@node, anchor: "profiling"), notice: "Profiling run started."
    end

    private

    def set_node
      @node = Node.find(params[:node_id])
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to node_path(@node), alert: "You are not authorized to run profiling."
    end

    def profiling_run_params
      params.require(:profiling_run).permit(:subcommand, :profiling_recipe_id, options: {})
    end

    def agent_token
      @node.effective_api_token.presence ||
        Rails.application.credentials.dig(:api, :agent_token) ||
        ENV["API_AGENT_TOKEN"]
    end
  end
end
