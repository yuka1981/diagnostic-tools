# frozen_string_literal: true

module Settings
  class AgentBinariesController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :set_agent_release
    before_action :set_agent_binary, only: :destroy

    def new
      @agent_binary = @agent_release.agent_binaries.build
      @available_architectures = available_architectures
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

    def destroy
      arch = @agent_binary.arch
      @agent_binary.destroy!
      redirect_to settings_agent_release_path(@agent_release),
                  notice: "Binary for #{arch} was successfully deleted."
    end

    private

    def build_mode?
      params[:creation_mode] == "build"
    end

    def create_from_upload
      @agent_binary = @agent_release.agent_binaries.build(agent_binary_params)

      if @agent_binary.save
        redirect_to settings_agent_release_path(@agent_release),
                    notice: "Binary for #{@agent_binary.arch} was successfully uploaded."
      else
        @available_architectures = available_architectures
        @go_available = Agent::CompilerService.go_available?
        @go_version = Agent::CompilerService.go_version if @go_available
        render :new, status: :unprocessable_entity
      end
    end

    def create_from_build
      target_arch = params[:target_arch]
      custom_ldflags = params[:custom_ldflags].presence

      # Use CompilerService to build and attach binary
      Agent::CompilerService.build_release(
        version_tag: @agent_release.version,
        arch: target_arch,
        custom_ldflags: custom_ldflags
      )

      redirect_to settings_agent_release_path(@agent_release),
                  notice: "Binary for #{target_arch} was successfully built from source."
    rescue Agent::CompilerService::CompilationError => e
      @agent_binary = @agent_release.agent_binaries.build(arch: target_arch)
      @agent_binary.errors.add(:base, "Compilation failed: #{e.message}")
      @available_architectures = available_architectures
      @go_available = Agent::CompilerService.go_available?
      @go_version = Agent::CompilerService.go_version if @go_available
      render :new, status: :unprocessable_entity
    end

    def set_agent_release
      @agent_release = AgentRelease.find(params[:agent_release_id])
    end

    def set_agent_binary
      @agent_binary = @agent_release.agent_binaries.find(params[:id])
    end

    def agent_binary_params
      params.require(:agent_binary).permit(:arch, :binary)
    end

    def available_architectures
      existing = @agent_release.agent_binaries.pluck(:arch)
      AgentBinary::SUPPORTED_ARCHITECTURES - existing
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to manage agent releases."
    end
  end
end
