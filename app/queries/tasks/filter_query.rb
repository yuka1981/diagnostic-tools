# frozen_string_literal: true

module Tasks
  # Query object for filtering and searching combined benchmark/profiling runs
  class FilterQuery
    VALID_TYPES = %w[benchmark profiling].freeze
    VALID_STATUSES = BenchmarkRun.statuses.keys.freeze
    DATE_RANGES = {
      "last_hour" => 1.hour,
      "last_24h" => 24.hours,
      "last_7d" => 7.days,
      "last_30d" => 30.days
    }.freeze

    attr_reader :params

    def initialize(params = {})
      @params = params.to_h.with_indifferent_access
      @cached_results = nil
    end

    def call
      @cached_results ||= fetch_and_merge_results
    end

    def total_count
      call.size
    end

    def filtered?
      type_filter.present? || status.present? || node_id.present? ||
        recipe_id.present? || search_query.present? || date_range.present?
    end

    # Accessors for form repopulation
    def type_filter
      params[:type].presence
    end

    def status
      params[:status].presence
    end

    def node_id
      params[:node_id].presence
    end

    def recipe_id
      params[:recipe_id].presence
    end

    def search_query
      params[:q].presence
    end

    def date_range
      params[:date_range].presence
    end

    private

    def fetch_and_merge_results
      benchmark_tasks = fetch_benchmark_runs.map { |r| Task.wrap(r) }
      profiling_tasks = fetch_profiling_runs.map { |r| Task.wrap(r) }

      (benchmark_tasks + profiling_tasks).sort_by { |t| -t.created_at.to_i }
    end

    def fetch_benchmark_runs
      return BenchmarkRun.none if type_filter == "profiling"

      scope = BenchmarkRun.includes(:node, :benchmark_recipe)
      scope = apply_common_filters(scope, :benchmark)
      scope = apply_recipe_filter(scope, :benchmark, :benchmark_recipe_id)
      scope = apply_benchmark_search(scope)
      scope
    end

    def fetch_profiling_runs
      return ProfilingRun.none if type_filter == "benchmark"

      scope = ProfilingRun.includes(:node, :profiling_recipe)
      scope = apply_common_filters(scope, :profiling)
      scope = apply_recipe_filter(scope, :profiling, :profiling_recipe_id)
      scope = apply_profiling_search(scope)
      scope
    end

    def apply_common_filters(scope, _type)
      scope = scope.where(status: status) if status.present? && VALID_STATUSES.include?(status)
      scope = scope.where(node_id: node_id) if node_id.present?
      scope = apply_date_range(scope) if date_range.present?
      scope
    end

    def apply_date_range(scope)
      duration = DATE_RANGES[date_range]
      return scope unless duration

      scope.where(created_at: duration.ago..)
    end

    def apply_recipe_filter(scope, expected_type, foreign_key)
      return scope unless recipe_id.present?

      parsed = Task.parse_param(recipe_id)
      return scope.none unless parsed

      type, id = parsed
      return scope.none unless type == expected_type

      scope.where(foreign_key => id)
    end

    def apply_benchmark_search(scope)
      return scope unless search_query.present?

      term = "%#{search_query}%"
      scope.joins(:node, :benchmark_recipe)
           .where("nodes.hostname ILIKE :term OR benchmark_recipes.name ILIKE :term OR benchmark_runs.uuid::text ILIKE :term", term: term)
    end

    def apply_profiling_search(scope)
      return scope unless search_query.present?

      term = "%#{search_query}%"
      scope.left_joins(:profiling_recipe)
           .joins(:node)
           .where("nodes.hostname ILIKE :term OR profiling_recipes.name ILIKE :term OR profiling_runs.uuid::text ILIKE :term OR profiling_runs.subcommand ILIKE :term", term: term)
    end
  end
end
