# frozen_string_literal: true

module Settings
  class AgentsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def show
      @ssh_setting = SshSetting.current
      @agent_releases = AgentRelease.latest_first
      @latest_release = AgentRelease.latest
    end

    def update
      @ssh_setting = SshSetting.current
      if @ssh_setting.update(agent_params)
        redirect_to settings_agent_path, notice: "Agent configuration updated successfully."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to access this page."
    end

    def agent_params
      params.require(:ssh_setting).permit(:server_url, :benchmark_work_dir)
    end
  end
end
