# frozen_string_literal: true

module Settings
  class ServerProductsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :set_server_product, only: %i[show edit update destroy]

    def index
      @server_products = ServerProduct.all
      @server_products = @server_products.by_series(params[:series]) if params[:series].present?
      @server_products = @server_products.by_form_factor(params[:form_factor]) if params[:form_factor].present?
      @server_products = @server_products.search_by_name(params[:q]) if params[:q].present?
      @server_products = @server_products.order(:name)
      @last_sync = SyncLog.for_source("qct").latest.first
    end

    def show
    end

    def new
      @server_product = ServerProduct.new
    end

    def create
      @server_product = ServerProduct.new(server_product_params)
      if @server_product.save
        redirect_to settings_server_products_path, notice: "Server product was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @server_product.update(server_product_params)
        redirect_to settings_server_products_path, notice: "Server product was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @server_product.destroy
      redirect_to settings_server_products_path, notice: "Server product was successfully deleted."
    end

    def sync
      QctSyncJob.perform_later
      redirect_to settings_server_products_path, notice: "Sync started. You'll be notified when complete."
    end

    private

    def set_server_product
      @server_product = ServerProduct.find(params[:id])
    end

    def server_product_params
      params.require(:server_product).permit(
        :name, :product_series, :form_factor, :rack_height, :qct_product_url,
        :socket_count, :max_tdp_watts, :max_memory_gb, :dimm_slots, :max_memory_speed_mhz,
        :gpu_support, :last_synced_at,
        cpu_generations: [], memory_types: [], drive_bays: [], pcie_slots: [],
        power_supply_options: [], network_options: [], images: []
      )
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to access this page."
    end
  end
end
