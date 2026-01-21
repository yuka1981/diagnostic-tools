# frozen_string_literal: true

class RoomsController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_room, only: %i[show edit update destroy]
  before_action :authorize_approver!, only: %i[new create edit update destroy]

  def index
    @rooms = Room.includes(:site, :server_racks).order(:name)
    @rooms = @rooms.where(site_id: params[:site_id]) if params[:site_id].present?
    @sites = Site.order(:name)
  end

  def show
    @server_racks = @room.server_racks.includes(:nodes).order(:name)
  end

  def new
    @room = Room.new
    @room.site_id = params[:site_id] if params[:site_id].present?
    @sites = Site.order(:name)
  end

  def create
    @room = Room.new(room_params)

    if @room.save
      redirect_to room_path(@room), notice: "Room was successfully created."
    else
      @sites = Site.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @sites = Site.order(:name)
  end

  def update
    if @room.update(room_params)
      redirect_to room_path(@room), notice: "Room was successfully updated."
    else
      @sites = Site.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @room.server_racks.any?
      redirect_to room_path(@room), alert: "Cannot delete room with racks. Remove all racks first."
    else
      @room.destroy
      redirect_to rooms_path, notice: "Room was successfully deleted."
    end
  end

  # API endpoint for cascading select
  def for_site
    @rooms = Room.where(site_id: params[:site_id]).order(:name)
    render json: @rooms.map { |r| { id: r.id, name: r.name } }
  end

  private

  def set_room
    @room = Room.includes(:site, server_racks: :nodes).find(params[:id])
  end

  def room_params
    params.require(:room).permit(
      :site_id, :name, :description,
      :floor_area_sqm, :power_capacity_kw, :cooling_capacity_kw, :max_rack_count,
      :floor_number, :building_wing, :grid_coordinates
    )
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to rooms_path, alert: "You are not authorized to manage rooms."
  end
end
