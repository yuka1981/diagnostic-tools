# frozen_string_literal: true

module Settings
  class SshDefaultsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def show
      @ssh_setting = SshSetting.current
    end

    def update
      @ssh_setting = SshSetting.current
      if @ssh_setting.update(ssh_params)
        redirect_to settings_ssh_defaults_path, notice: "SSH defaults updated successfully."
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
      params.require(:ssh_setting).permit(
        :bastion_host, :bastion_user, :bastion_port,
        :ssh_user, :ssh_port, :ssh_key, :ssh_password, :sudo_credential,
        :timeout, :verify_host_key
      )
    end
  end
end
