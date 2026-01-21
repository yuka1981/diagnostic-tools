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
      # Store credentials in cache for the job to retrieve
      credentials_cache_key = SecureRandom.hex(16)
      credentials = {}
      credentials[:sudo_password] = params[:sudo_password] if params[:sudo_password].present?
      credentials[:ssh_password] = params[:ssh_password] if params[:ssh_password].present?

      if credentials.any?
        Rails.cache.write(
          "update_creds_#{credentials_cache_key}",
          credentials,
          expires_in: 5.minutes
        )
      end

      # Enqueue the update job
      Agent::UpdateJob.perform_later(
        node: @node,
        agent_release: @agent_release,
        force: params[:force] == "true",
        credentials_cache_key: credentials.any? ? credentials_cache_key : nil,
        user_id: current_user.id
      )

      # Respond with turbo_stream to show progress UI
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to node_path(@node), notice: "Agent update started" }
      end
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
