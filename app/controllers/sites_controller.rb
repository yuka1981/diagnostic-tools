# frozen_string_literal: true

class SitesController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_site, only: %i[show edit update destroy]
  before_action :authorize_approver!, only: %i[new create edit update destroy]

  def index
    @sites = Site.order(:name)
  end

  def show
  end

  def new
    @site = Site.new
  end

  def create
    @site = Site.new(site_params)

    if @site.save
      redirect_to sites_path, notice: "Site was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @site.update(site_params)
      redirect_to sites_path, notice: "Site was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @site.destroy
    redirect_to sites_path, notice: "Site was successfully deleted."
  end

  private

  def set_site
    @site = Site.find(params[:id])
  end

  def site_params
    params.require(:site).permit(:name, :description)
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to sites_path, alert: "You are not authorized to manage sites."
  end
end
