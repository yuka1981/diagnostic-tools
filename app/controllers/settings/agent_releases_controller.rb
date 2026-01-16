# frozen_string_literal: true

module Settings
  class AgentReleasesController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :set_agent_release, only: %i[show edit update destroy deprecate activate recall]

    def index
      @agent_releases = AgentRelease.latest_first
      @latest_release = AgentRelease.latest
    end

    def show
    end

    def new
      @agent_release = AgentRelease.new
      @go_available = Agent::CompilerService.go_available?
      @go_version = Agent::CompilerService.go_version if @go_available
    end

    def create
      if build_mode?
        create_from_build
      else
        create_from_upload
      end
    end

    def edit
    end

    def update
      if @agent_release.update(agent_release_params)
        redirect_to settings_agent_release_path(@agent_release),
                    notice: "Agent release was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      version = @agent_release.version
      @agent_release.destroy!
      redirect_to settings_agent_releases_path,
                  notice: "Agent release #{version} was successfully deleted."
    end

    # Status transition actions
    def deprecate
      @agent_release.deprecated!
      redirect_to settings_agent_release_path(@agent_release),
                  notice: "Agent release #{@agent_release.version} has been deprecated."
    end

    def activate
      @agent_release.active!
      redirect_to settings_agent_release_path(@agent_release),
                  notice: "Agent release #{@agent_release.version} has been activated."
    end

    def recall
      @agent_release.recalled!
      redirect_to settings_agent_release_path(@agent_release),
                  alert: "Agent release #{@agent_release.version} has been recalled."
    end

    private

    def build_mode?
      params[:creation_mode] == "build"
    end

    def create_from_upload
      @agent_release = AgentRelease.new(agent_release_params)

      if @agent_release.save
        redirect_to settings_agent_release_path(@agent_release),
                    notice: "Agent release #{@agent_release.version} was successfully uploaded."
      else
        @go_available = Agent::CompilerService.go_available?
        @go_version = Agent::CompilerService.go_version if @go_available
        render :new, status: :unprocessable_entity
      end
    end

    def create_from_build
      version = params.dig(:agent_release, :version)
      release_notes = params.dig(:agent_release, :release_notes)

      @agent_release = Agent::CompilerService.build_release(
        version_tag: version,
        release_notes: release_notes
      )

      redirect_to settings_agent_release_path(@agent_release),
                  notice: "Agent release #{@agent_release.version} was successfully built from source."
    rescue Agent::CompilerService::CompilationError => e
      @agent_release = AgentRelease.new(version: version, release_notes: release_notes)
      @agent_release.errors.add(:base, "Compilation failed: #{e.message}")
      @go_available = Agent::CompilerService.go_available?
      @go_version = Agent::CompilerService.go_version if @go_available
      render :new, status: :unprocessable_entity
    end

    def set_agent_release
      @agent_release = AgentRelease.find(params[:id])
    end

    def agent_release_params
      params.require(:agent_release).permit(:version, :release_notes, :status, :binary)
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to manage agent releases."
    end
  end
end
