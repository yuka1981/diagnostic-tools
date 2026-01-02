# frozen_string_literal: true

class NodesController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_node, only: %i[show edit update destroy test_connection]
  before_action :authorize_approver!, only: %i[new create edit update destroy]

  def index
    @nodes = Node.order(:hostname)
  end

  def show; end

  def test_connection
    service = Inventory::TriggerCollectService.new(@node)
    result = service.call

    respond_to do |format|
      format.turbo_stream do
        if result.success?
          flash.now[:notice] = "Connection to #{@node.hostname} successful!"
        else
          flash.now[:alert] = "Connection to #{@node.hostname} failed: #{result.error}"
        end
        render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
      end
    end
  rescue StandardError => e
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = "Connection error: #{e.message}"
        render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
      end
    end
  end

  def new
    @node = Node.new
  end

  def create
    @node = Node.new(node_params)
    @node.role = params[:node][:role] if params[:node][:role].present?
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
    @node.role = params[:node][:role] if params[:node][:role].present?
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
    params.require(:node).permit(:hostname, :ip, :arch, :ssh_port, :ssh_user, :agent_path, :jump_host, :jump_user, :jump_port)
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to nodes_path, alert: "You are not authorized to manage nodes."
  end
end
