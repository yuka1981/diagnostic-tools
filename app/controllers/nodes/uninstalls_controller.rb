# frozen_string_literal: true

module Nodes
  class UninstallsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def new
      @target_host = params[:hostname]
    end

    def create
      # Store sensitive credentials in a short-lived cache
      cache_key = SecureRandom.hex(16)
      credentials = {
        bastion_password: uninstall_params[:bastion_password],
        sudo_password: uninstall_params[:sudo_password]
      }
      Rails.cache.write("install_creds_#{cache_key}", credentials, expires_in: 5.minutes)

      Agent::UninstallJob.perform_later(
        target_host: uninstall_params[:hostname],
        bastion_host: uninstall_params[:bastion_host],
        bastion_user: uninstall_params[:bastion_user],
        credentials_cache_key: cache_key
      )

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to nodes_path, notice: "Uninstallation started for #{uninstall_params[:hostname]}" }
      end
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to nodes_path, alert: "You are not authorized to manage agents."
    end

    def uninstall_params
      params.require(:uninstall).permit(:hostname, :bastion_host, :bastion_user, :bastion_password, :sudo_password)
    end
  end
end
