# frozen_string_literal: true

module Bmc
  class StatusCardComponent < ViewComponent::Base
    def initialize(node:)
      @node = node
    end

    def bmc_configured?
      @node.bmc_address.present?
    end

    def latest_inventory
      @latest_inventory ||= @node.latest_bmc_inventory
    end

    def health_status
      return :unknown unless latest_inventory

      # Derive health from bmc_info or sensors
      bmc_info = latest_inventory.bmc_info || {}
      bmc_info["health"]&.downcase&.to_sym || :ok
    end

    def health_badge_classes
      base = "px-2 py-0.5 rounded text-xs font-bold shadow-sm"
      case health_status
      when :ok, :healthy
        "#{base} bg-success-2 text-success-7 border border-success-2"
      when :warning
        "#{base} bg-warning-1 text-warning-7 border border-warning-2"
      when :critical, :error
        "#{base} bg-error-1 text-error-7 border border-error-2"
      else
        "#{base} bg-neutral-4 text-neutral-85 border border-neutral-8"
      end
    end

    def protocol_label
      credential = @node.bmc_credential_for_connection
      credential&.protocol&.humanize || "Auto"
    end

    def last_collected_at
      latest_inventory&.captured_at
    end

    def unresolved_discrepancy_count
      @node.unresolved_discrepancies.count
    end

    def has_discrepancies?
      unresolved_discrepancy_count > 0
    end
  end
end
