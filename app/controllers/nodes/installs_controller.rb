# frozen_string_literal: true

module Nodes
  class InstallsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def new
      @target_host = params[:hostname]
    end

    def create
      Agent::InstallJob.perform_later(
        target_host: install_params[:hostname],
        arch: install_params[:arch],
        bastion_user: install_params[:bastion_user],
        bastion_password: install_params[:bastion_password],
        sudo_password: install_params[:sudo_password],
        server_url: request.base_url
      )

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to nodes_path, notice: "Installation started for #{install_params[:hostname]}" }
      end
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to nodes_path, alert: "You are not authorized to install agents."
    end

    def install_params
      params.require(:install).permit(:hostname, :arch, :bastion_user, :bastion_password, :sudo_password)
    end
  end
end
