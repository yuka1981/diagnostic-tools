# frozen_string_literal: true

module Nodes
  class InstallsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def new
      @target_host = params[:hostname]
      @arch = params[:arch]
      @api_keys = ApiKey.active.order(:name)
    end

    def create
      # Find selected API key token if provided
      selected_token = ApiKey.active.find_by(id: install_params[:api_key_id])&.token

      # Store sensitive credentials in a short-lived cache to avoid passing them as job arguments
      cache_key = SecureRandom.hex(16)
      credentials = {
        bastion_password: install_params[:bastion_password],
        sudo_password: install_params[:sudo_password],
        agent_token: selected_token # Optional override for agent token
      }
      Rails.cache.write("install_creds_#{cache_key}", credentials, expires_in: 5.minutes)

      Agent::InstallJob.perform_later(
        target_host: install_params[:hostname],
        arch: install_params[:arch],
        bastion_host: install_params[:bastion_host],
        bastion_user: install_params[:bastion_user],
        credentials_cache_key: cache_key,
        server_url: install_params[:server_url].presence || request.base_url
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
      params.require(:install).permit(:hostname, :arch, :server_url, :api_key_id, :bastion_host, :bastion_user, :bastion_password, :sudo_password)
    end
  end
end
