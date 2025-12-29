# frozen_string_literal: true

class DashboardController < ApplicationController
  layout "dashboard"

  def index
    metrics = Dashboard::MetricsService.new.call

    @total_nodes = metrics.total_nodes
    @online_nodes = metrics.online_nodes
    @availability_percentage = metrics.availability_percentage
    @success_rate_24h = metrics.success_rate_24h
    @runs_by_status = metrics.runs_by_status
    @nodes_by_role = metrics.nodes_by_role

    # Load all nodes for heatmap display
    @nodes = Node.order(:hostname)

    # Handle node filtering for benchmark runs
    @selected_node = Node.find_by(id: params[:node_id])

    # Load runs with optional node filter
    runs_scope = BenchmarkRun.recent.includes(:node, :benchmark_recipe)
    runs_scope = runs_scope.for_node(@selected_node) if @selected_node
    @filtered_runs = runs_scope.limit(10)
  end
end
