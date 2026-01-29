# frozen_string_literal: true

class NodesController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_node, only: %i[show edit update destroy test_connection collect run_benchmark]
  before_action :authorize_approver!, only: %i[new create edit update destroy bulk_destroy test_connection collect run_benchmark]

  def index
    @nodes = Node.order(:hostname)
  end

  def show
    @selected_state = if params[:state_id].present?
                        @node.node_states.find(params[:state_id])
    else
                        @node.current_state
    end
  end

  def test_connection
    salt_client = SaltApiClient.new
    salt_client.run(@node.hostname, "test.ping")

    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = "Connection to #{@node.hostname} successful!"
        render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
      end
    end
  rescue SaltApiClient::TargetUnreachable => e
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = "Connection to #{@node.hostname} failed: #{e.message}"
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

  def collect
    service = Inventory::SaltCollectService.new(@node)
    result = service.call

    if result.success?
      flash.now[:notice] = "System information collected successfully for #{@node.hostname}."
    else
      flash.now[:alert] = "Failed to collect information from #{@node.hostname}: #{result.error}"
    end

    @node.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @node }
    end
  rescue StandardError => e
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = "Collection error: #{e.message}"
        render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
      end
      format.html { redirect_to @node, alert: "Collection error: #{e.message}" }
    end
  end

  def run_benchmark
    trigger_service = Benchmark::TriggerRunService.new(@node)
    result = trigger_service.call

    if result.success?
      redirect_to benchmark_runs_path(node_id: @node.id), notice: "Benchmark triggered successfully. Results will appear here shortly."
    else
      redirect_to @node, alert: "Failed to trigger benchmark: #{result.error}"
    end
  end

  def new
    @node = Node.new
    @api_keys = ApiKey.active.order(:name)
  end

  def create
    if bulk_pattern?(params[:node][:hostname])
      create_bulk
    else
      create_single
    end
  end

  def edit
    @api_keys = ApiKey.active.order(:name)
  end

  def update
    if @node.update(node_params)
      respond_to do |format|
        format.html {
          if from_show_page?
            redirect_to @node, notice: "Node was successfully updated."
          else
            redirect_to nodes_path, notice: "Node was successfully updated."
          end
        }
        format.turbo_stream {
          flash.now[:notice] = "Node was successfully updated."
        }
      end
    else
      @api_keys = ApiKey.active.order(:name)
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

  def bulk_destroy
    node_ids = params[:node_ids] || []
    @deleted_nodes = Node.where(id: node_ids).to_a
    deleted_count = @deleted_nodes.each(&:destroy).count

    respond_to do |format|
      format.turbo_stream {
        flash.now[:notice] = "#{deleted_count} nodes deleted."
      }
      format.html {
        redirect_to nodes_path, notice: "#{deleted_count} nodes deleted."
      }
    end
  end

  private

  def set_node
    @node = Node.find(params[:id])
  end

  def node_params
    params.require(:node).permit(
      :hostname, :ip, :role, :arch, :ssh_port, :ssh_user, :ssh_key, :ssh_password,
      :sudo_credential, :ssh_connect_method, :agent_path, :benchmark_work_dir,
      :api_key_id, :rack_id, :rack_position, :rack_height, :server_product_id,
      :ssh_user_override, :ssh_port_override, :ssh_key_override, :ssh_password_override,
      :sudo_credential_override, :ssh_connect_method_override
    )
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to nodes_path, alert: "You are not authorized to manage nodes."
  end

  def create_single
    @node = Node.new(node_params)
    @node.source = :manual

    if @node.save
      respond_to do |format|
        format.html { redirect_to nodes_path, notice: "Node was successfully created." }
        format.turbo_stream
      end
    else
      @api_keys = ApiKey.active.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def create_bulk
    service = Nodes::BulkCreateService.new(
      params[:node][:hostname],
      node_params.except(:hostname),
      params[:node_overrides] || {}
    )
    result = service.call

    if result.success?
      @nodes = result.nodes
      respond_to do |format|
        format.html { redirect_to nodes_path, notice: "#{@nodes.count} nodes were successfully created." }
        format.turbo_stream { render :create_bulk }
      end
    else
      @node = Node.new(node_params)
      if result.conflicts.any?
        @node.errors.add(:hostname, "has conflicts: #{result.conflicts.join(', ')}")
      else
        @node.errors.add(:hostname, result.error)
      end
      @api_keys = ApiKey.active.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def bulk_pattern?(hostname)
    hostname.to_s.match?(/\[(\d+)-(\d+)\]/)
  end

  def from_show_page?
    request.referer&.match?(%r{/nodes/\d+(?:\?|$)})
  end
end
