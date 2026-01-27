# frozen_string_literal: true

module Bmc
  class DiscrepancyPanelComponent < ViewComponent::Base
    def initialize(node:)
      @node = node
    end

    def discrepancies
      @discrepancies ||= @node.inventory_discrepancies.unresolved.order(severity: :desc, created_at: :desc)
    end

    def has_discrepancies?
      discrepancies.any?
    end

    def severity_badge_classes(severity)
      base = "px-2 py-0.5 rounded text-xs font-bold"
      case severity.to_s
      when "critical"
        "#{base} bg-error-1 text-error-7 border border-error-2"
      when "warning"
        "#{base} bg-warning-1 text-warning-7 border border-warning-2"
      else # info
        "#{base} bg-primary-1 text-primary-7 border border-primary-2"
      end
    end

    def severity_icon(severity)
      case severity.to_s
      when "critical" then "alert-circle"
      when "warning" then "alert-triangle"
      else "info"
      end
    end
  end
end
