# frozen_string_literal: true

module Nodes
  # Form Object for filtering and searching nodes
  # Composes SQL queries based on filter parameters
  class FilterQuery
    VALID_ROLES = Node.roles.keys.freeze
    VALID_STATUSES = %w[online offline].freeze

    attr_reader :params

    def initialize(params = {})
      @params = params.to_h.with_indifferent_access
    end

    def call
      %i[
        filter_by_role
        filter_by_status
        filter_by_search
      ].reduce(base_scope) { |scope, filter| send(filter, scope) }
    end

    def filtered?
      role.present? || status.present? || search_query.present?
    end

    # Accessors for filter values
    def role
      params[:role].presence
    end

    def status
      params[:status].presence
    end

    def search_query
      params[:q].presence
    end

    private

    def base_scope
      Node.order(:hostname)
    end

    def filter_by_role(scope)
      return scope unless role.present? && VALID_ROLES.include?(role)

      scope.where(role: role)
    end

    def filter_by_status(scope)
      return scope unless status.present? && VALID_STATUSES.include?(status)

      case status
      when "online"
        scope.online
      when "offline"
        scope.where.not(id: Node.online)
      else
        scope
      end
    end

    def filter_by_search(scope)
      return scope unless search_query.present?

      search_term = "%#{search_query}%"
      scope.where("hostname ILIKE :term OR ip ILIKE :term", term: search_term)
    end
  end
end
