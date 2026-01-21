# frozen_string_literal: true

class ServerRacksController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_server_rack, only: %i[show edit update destroy update_layout]
  before_action :authorize_approver!, only: %i[new create edit update destroy update_layout]

  def index
    @server_racks = ServerRack.includes(room: :site).includes(:nodes).order(:name)
    @server_racks = @server_racks.joins(:room).where(rooms: { site_id: params[:site_id] }) if params[:site_id].present?
    @sites = Site.order(:name)
  end

  def show
  end

  def new
    @server_rack = ServerRack.new
    @server_rack.room_id = params[:room_id] if params[:room_id].present?
    @rooms = Room.includes(:site).order(:name)
  end

  def create
    @server_rack = ServerRack.new(server_rack_params)

    if @server_rack.save
      redirect_to server_racks_path, notice: "Rack was successfully created."
    else
      @rooms = Room.includes(:site).order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @rooms = Room.includes(:site).order(:name)
  end

  def update
    if @server_rack.update(server_rack_params)
      redirect_to server_racks_path, notice: "Rack was successfully updated."
    else
      @rooms = Room.includes(:site).order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @server_rack.destroy
    redirect_to server_racks_path, notice: "Rack was successfully deleted."
  end

  def update_layout
    service = Racks::UpdateLayoutService.new(@server_rack, params[:positions])
    result = service.call

    render json: { success: result.success?, errors: result.errors }
  end

  private

  def set_server_rack
    @server_rack = ServerRack.includes(room: :site).includes(:nodes).find(params[:id])
  end

  def server_rack_params
    params.require(:server_rack).permit(:room_id, :name, :u_height, :status, :facility_id, :asset_tag, :desc_units)
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to server_racks_path, alert: "You are not authorized to manage racks."
  end
end
