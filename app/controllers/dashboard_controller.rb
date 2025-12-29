# frozen_string_literal: true

class DashboardController < ApplicationController
  layout "dashboard"

  def index
    @total_nodes = Node.count
    @online_nodes = Node.online.count
    @recent_runs = BenchmarkRun.recent.includes(:node, :benchmark_recipe).limit(5)
    @success_rate_24h = calculate_success_rate
  end

  private

  def calculate_success_rate
    runs_24h = BenchmarkRun.in_last_24_hours.completed
    # Group by status and count in a single query
    status_counts = runs_24h.group(:status).count

    total = status_counts.values.sum
    return 0 if total.zero?

    successful = status_counts[BenchmarkRun.statuses[:success]].to_i
    (successful.to_f / total * 100).round(1)
  end
end
