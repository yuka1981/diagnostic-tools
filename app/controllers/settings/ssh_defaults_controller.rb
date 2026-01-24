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
      update_params = ssh_params.to_h

      # Handle credential clear flags
      update_params[:ssh_key] = nil if update_params.delete(:clear_ssh_key) == "1"
      update_params[:ssh_password] = nil if update_params.delete(:clear_ssh_password) == "1"
      update_params[:sudo_credential] = nil if update_params.delete(:clear_sudo_credential) == "1"

      if @ssh_setting.update(update_params)
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
        :timeout, :verify_host_key,
        :clear_ssh_key, :clear_ssh_password, :clear_sudo_credential
      )
    end
  end
end
