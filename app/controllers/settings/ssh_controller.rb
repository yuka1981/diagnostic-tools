# frozen_string_literal: true

module Settings
  class SshController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def show
      @ssh_setting = SshSetting.current
    end

    def update
      @ssh_setting = SshSetting.current
      if @ssh_setting.update(ssh_params)
        redirect_to settings_ssh_path, notice: "SSH settings updated successfully."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to access this page."
    end

    def ssh_params
      params.require(:ssh_setting).permit(:bastion_host, :bastion_user, :bastion_port, :server_url)
    end
  end
end
