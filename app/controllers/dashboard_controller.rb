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

    @recent_runs = BenchmarkRun.recent.includes(:node, :benchmark_recipe).limit(5)
  end
end
