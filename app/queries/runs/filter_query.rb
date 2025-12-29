# frozen_string_literal: true

module Runs
  # Form Object for filtering and searching benchmark runs
  # Composes SQL queries based on filter parameters
  class FilterQuery
    VALID_STATUSES = BenchmarkRun.statuses.keys.freeze

    attr_reader :params

    def initialize(params = {})
      @params = params.to_h.with_indifferent_access
    end

    def call
      %i[
        filter_by_status
        filter_by_node
        filter_by_recipe
        filter_by_search
      ].reduce(base_scope) { |scope, filter| send(filter, scope) }
    end

    def filtered?
      status.present? || node_id.present? || recipe_id.present? || search_query.present?
    end

    # Accessors for filter values (useful for form repopulation)
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

    private

    def base_scope
      BenchmarkRun.recent.includes(:node, :benchmark_recipe)
    end

    def filter_by_status(scope)
      return scope unless status.present? && VALID_STATUSES.include?(status)

      scope.where(status: status)
    end

    def filter_by_node(scope)
      return scope unless node_id.present?

      scope.where(node_id: node_id)
    end

    def filter_by_recipe(scope)
      return scope unless recipe_id.present?

      scope.where(benchmark_recipe_id: recipe_id)
    end

    def filter_by_search(scope)
      return scope unless search_query.present?

      search_term = "%#{search_query}%"
      scope.joins(:node, :benchmark_recipe)
           .where("nodes.hostname ILIKE :term OR benchmark_recipes.name ILIKE :term", term: search_term)
    end
  end
end
