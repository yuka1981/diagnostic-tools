# frozen_string_literal: true

module Bmc
  class InventoryComponent < ViewComponent::Base
    TABS = %w[processors memory storage network infiniband bios].freeze

    def initialize(node:, active_tab: "processors")
      @node = node
      @active_tab = active_tab
    end

    def inventory
      @inventory ||= @node.latest_bmc_inventory
    end

    def has_inventory?
      inventory.present?
    end

    def tabs
      TABS.map do |tab|
        {
          id: tab,
          label: tab.titleize,
          icon: tab_icon(tab),
          count: item_count(tab),
          active: @active_tab == tab
        }
      end
    end

    def processors
      inventory&.processors || []
    end

    def memory
      inventory&.memory || []
    end

    def storage
      inventory&.storage || []
    end

    def network
      inventory&.network || []
    end

    def infiniband
      inventory&.infiniband || []
    end

    def bios
      inventory&.bios || {}
    end

    def collection_method
      inventory&.collection_method&.humanize || "Unknown"
    end

    def captured_at
      inventory&.captured_at
    end

    private

    def tab_icon(tab)
      case tab
      when "processors" then "cpu"
      when "memory" then "memory-stick"
      when "storage" then "hard-drive"
      when "network" then "network"
      when "infiniband" then "cable"
      when "bios" then "settings"
      else "file"
      end
    end

    def item_count(tab)
      case tab
      when "bios" then nil
      else send(tab)&.size || 0
      end
    end
  end
end
