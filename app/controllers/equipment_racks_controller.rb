# frozen_string_literal: true

class EquipmentRacksController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_equipment_rack, only: %i[show edit update destroy]
  before_action :authorize_approver!, only: %i[new create edit update destroy]

  def index
    @equipment_racks = EquipmentRack.includes(:room).order(:name)
  end

  def show
    @nodes = @equipment_rack.nodes.order(:rack_position)
    @face = params[:face]&.to_sym || :front

    respond_to do |format|
      format.html
      format.turbo_stream { render_elevation_frame }
    end
  end

  def new
    @equipment_rack = EquipmentRack.new
    @rooms = Room.order(:name)
  end

  def create
    @equipment_rack = EquipmentRack.new(equipment_rack_params)

    if @equipment_rack.save
      respond_to do |format|
        format.html { redirect_to equipment_racks_path, notice: "Rack was successfully created." }
        format.turbo_stream
      end
    else
      @rooms = Room.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @rooms = Room.order(:name)
  end

  def update
    if @equipment_rack.update(equipment_rack_params)
      respond_to do |format|
        format.html { redirect_to equipment_racks_path, notice: "Rack was successfully updated." }
        format.turbo_stream {
          flash.now[:notice] = "Rack was successfully updated."
        }
      end
    else
      @rooms = Room.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @equipment_rack.destroy
    respond_to do |format|
      format.html { redirect_to equipment_racks_path, notice: "Rack was successfully deleted." }
      format.turbo_stream
    end
  end

  private

  def set_equipment_rack
    @equipment_rack = EquipmentRack.find(params[:id])
  end

  def equipment_rack_params
    params.require(:equipment_rack).permit(:name, :room_id, :row, :u_height, :width, :notes)
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to equipment_racks_path, alert: "You are not authorized to manage racks."
  end

  def render_elevation_frame
    render turbo_stream: turbo_stream.replace(
      "rack_elevation_#{@equipment_rack.id}",
      RackElevationComponent.new(rack: @equipment_rack, face: @face)
    )
  end
end
