# frozen_string_literal: true

module Nodes
  class UpdatesController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :set_node
    before_action :set_agent_release, only: :create

    def new
      @agent_releases = AgentRelease.active.latest_first
      @latest_release = AgentRelease.latest
    end

    def create
      service = Agent::PatchService.new(
        node: @node,
        agent_release: @agent_release,
        force: params[:force] == "true"
      )

      result = service.call
      redirect_to node_path(@node), notice: result.message
    rescue Agent::NodeBusyError
      redirect_to node_path(@node),
                  alert: "Cannot update Agent: The node is currently busy. Please wait for tasks to finish or cancel them."
    rescue Agent::PatchService::PatchError => e
      redirect_to node_path(@node), alert: "Agent update failed: #{e.message}"
    end

    private

    def set_node
      @node = Node.find(params[:node_id])
    end

    def set_agent_release
      @agent_release = AgentRelease.find(params[:agent_release_id])
    end

    def authorize_approver!
      return if current_user.approver?

      redirect_to nodes_path, alert: "You are not authorized to update agents."
    end
  end
end
