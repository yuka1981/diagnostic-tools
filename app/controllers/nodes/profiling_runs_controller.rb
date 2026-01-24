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

      validated_path = validate_artifact_path(artifact.file_path)

      if validated_path.nil?
        redirect_to node_profiling_run_path(@node, @run), alert: "Artifact path is not allowed."
        return
      end

      if artifact.downloadable?
        send_file validated_path,
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
      form = Profiling::RunForm.new(profiling_run_params)

      unless form.valid?
        @form = form
        @profiling_recipes = ProfilingRecipe.active.order(:name)
        render :new, status: :unprocessable_entity
        return
      end

      run = @node.profiling_runs.create!(
        subcommand: form.subcommand,
        options: form.options,
        profiling_recipe_id: form.profiling_recipe_id,
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
      params.require(:profiling_run).permit(:subcommand, :profiling_recipe_id, :duration, options: [ :duration ])
    end

    def validate_artifact_path(file_path)
      return nil if file_path.blank?

      base_directory = profiling_artifacts_base_directory
      expanded_path = File.expand_path(file_path)

      return nil unless expanded_path.start_with?("#{base_directory}#{File::SEPARATOR}")

      expanded_path
    end

    def profiling_artifacts_base_directory
      @profiling_artifacts_base_directory ||= begin
        base_path = ENV.fetch("PROFILING_ARTIFACTS_PATH") { "/shared/profiling_artifacts" }
        File.expand_path(base_path)
      end
    end

    def agent_token
      @node.effective_api_token.presence ||
        Rails.application.credentials.dig(:api, :agent_token) ||
        ENV["API_AGENT_TOKEN"]
    end
  end
end
