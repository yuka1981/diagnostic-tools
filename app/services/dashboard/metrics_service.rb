# frozen_string_literal: true

module Dashboard
  class MetricsService
    Result = Struct.new(
      :total_nodes,
      :online_nodes,
      :availability_percentage,
      :total_runs_24h,
      :successful_runs_24h,
      :failed_runs_24h,
      :success_rate_24h,
      :runs_by_status,
      :nodes_by_role,
      keyword_init: true
    )

    DEFAULT_TIME_RANGE = 24.hours

    # Initialize the service
    # @param time_range [ActiveSupport::Duration] Time range for run metrics (default: 24 hours)
    def initialize(time_range: DEFAULT_TIME_RANGE)
      @time_range = time_range
      @result = nil
    end

    # Calculate all dashboard metrics
    # @param refresh [Boolean] Force recalculation (bypass memoization)
    # @return [Result] Struct containing all metrics
    def call(refresh: false)
      return @result if @result && !refresh

      @result = Result.new(
        total_nodes: calculate_total_nodes,
        online_nodes: calculate_online_nodes,
        availability_percentage: calculate_availability,
        total_runs_24h: calculate_total_completed_runs,
        successful_runs_24h: run_status_counts[:success].to_i,
        failed_runs_24h: run_status_counts[:failed].to_i,
        success_rate_24h: calculate_success_rate,
        runs_by_status: symbolized_run_status_counts,
        nodes_by_role: symbolized_node_role_counts
      )
    end

    private

    # Node metrics
    def calculate_total_nodes
      @total_nodes ||= Node.count
    end

    def calculate_online_nodes
      @online_nodes ||= Node.online.count
    end

    def calculate_availability
      return 0.0 if calculate_total_nodes.zero?

      (calculate_online_nodes.to_f / calculate_total_nodes * 100).round(1)
    end

    def node_role_counts
      @node_role_counts ||= Node.group(:role).count
    end

    def symbolized_node_role_counts
      node_role_counts.transform_keys { |k| k.to_s.to_sym }
    end

    # Run metrics
    def completed_runs_in_range
      @completed_runs_in_range ||= BenchmarkRun
        .where(started_at: @time_range.ago..)
        .completed
    end

    def run_status_counts
      @run_status_counts ||= begin
        counts = completed_runs_in_range.group(:status).count
        # Convert string status keys to symbol keys
        # ActiveRecord enum stores as integer but returns string keys when grouped
        counts.transform_keys { |k| k.to_s.to_sym }
      end
    end

    def symbolized_run_status_counts
      run_status_counts.transform_keys(&:to_sym)
    end

    def calculate_total_completed_runs
      run_status_counts.values.sum
    end

    def calculate_success_rate
      total = calculate_total_completed_runs
      return 0.0 if total.zero?

      successful = run_status_counts[:success].to_i
      (successful.to_f / total * 100).round(1)
    end
  end
end
