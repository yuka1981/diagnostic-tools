# frozen_string_literal: true

module Settings
  class SshProfilesController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :set_ssh_profile, only: %i[edit update destroy]

    def index
      @ssh_profiles = SshProfile.includes(:nodes).order(:name)
    end

    def new
      @ssh_profile = SshProfile.new
    end

    def create
      @ssh_profile = SshProfile.new(ssh_profile_params)
      if @ssh_profile.save
        redirect_to settings_ssh_profiles_path, notice: "SSH profile was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @ssh_profile.update(ssh_profile_params)
        redirect_to settings_ssh_profiles_path, notice: "SSH profile was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @ssh_profile.destroy
      redirect_to settings_ssh_profiles_path, notice: "SSH profile was successfully deleted."
    end

    private

    def set_ssh_profile
      @ssh_profile = SshProfile.find(params[:id])
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to manage SSH profiles."
    end

    def ssh_profile_params
      params.require(:ssh_profile).permit(
        :name,
        :ssh_connect_method,
        :ssh_port,
        :ssh_user,
        :ssh_password,
        :ssh_key,
        :sudo_credential,
        :jump_host,
        :jump_user,
        :jump_port
      )
    end
  end
end
