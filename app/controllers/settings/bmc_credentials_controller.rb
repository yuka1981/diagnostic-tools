# frozen_string_literal: true

module Settings
  class BmcCredentialsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def show
      @credential = BmcCredential.global_default || BmcCredential.new(is_global_default: true)
    end

    def update
      @credential = BmcCredential.global_default || BmcCredential.new(is_global_default: true)

      if params[:bmc_credential][:password].blank?
        params[:bmc_credential].delete(:password)
      end

      if @credential.update(credential_params)
        redirect_to settings_bmc_credentials_path, notice: "BMC credentials updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to access this page."
    end

    def credential_params
      params.require(:bmc_credential).permit(:bmc_address, :username, :password, :protocol, :port, :verify_ssl)
    end
  end
end
