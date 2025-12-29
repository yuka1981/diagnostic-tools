# frozen_string_literal: true

class DashboardController < ApplicationController
  layout "dashboard"

  def index
    @total_nodes = Node.count
    @online_nodes = Node.all.count(&:online?)
    @recent_runs = BenchmarkRun.recent.limit(5)
    @success_rate_24h = calculate_success_rate
  end

  private

  def calculate_success_rate
    runs_24h = BenchmarkRun.in_last_24_hours.completed
    return 0 if runs_24h.empty?

    successful = runs_24h.count(&:success?)
    (successful.to_f / runs_24h.count * 100).round(1)
  end
end
