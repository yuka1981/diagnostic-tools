# frozen_string_literal: true

class NodesController < ApplicationController
  layout "dashboard"
  before_action :set_node, only: %i[show edit update destroy]

  def index
    @nodes = Node.order(:hostname)
  end

  def show; end

  def new
    @node = Node.new
  end

  def create
    @node = Node.new(node_params)
    @node.source = :manual

    if @node.save
      respond_to do |format|
        format.html { redirect_to nodes_path, notice: "Node was successfully created." }
        format.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @node.update(node_params)
      respond_to do |format|
        format.html { redirect_to nodes_path, notice: "Node was successfully updated." }
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @node.destroy
    respond_to do |format|
      format.html { redirect_to nodes_path, notice: "Node was successfully deleted." }
      format.turbo_stream
    end
  end

  private

  def set_node
    @node = Node.find(params[:id])
  end

  def node_params
    params.require(:node).permit(:hostname, :ip, :role, :arch, :ssh_port, :ssh_user)
  end
end
