# frozen_string_literal: true

class RoomsController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_room, only: %i[show edit update destroy]
  before_action :authorize_approver!, only: %i[new create edit update destroy]

  def index
    @rooms = Room.order(:name)
  end

  def show
  end

  def new
    @room = Room.new
  end

  def create
    @room = Room.new(room_params)

    if @room.save
      redirect_to @room, notice: "Room was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @room.update(room_params)
      redirect_to @room, notice: "Room was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @room.destroy
      redirect_to rooms_path, notice: "Room was successfully deleted."
    else
      redirect_to rooms_path, alert: "Cannot delete room: #{@room.errors.full_messages.join(', ')}"
    end
  end

  private

  def set_room
    @room = Room.find(params[:id])
  end

  def room_params
    params.require(:room).permit(:name, :description)
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to rooms_path, alert: "You are not authorized to manage rooms."
  end
end
