# frozen_string_literal: true

module Bmc
  class InventoryIngestionService
    def initialize(event_data)
      @results = event_data["results"] || []
    end

    def call
      created = []

      @results.each do |result|
        node = Node.find_by(id: result["node_id"])
        next unless node

        inventory = node.bmc_inventories.create!(
          processors: result["inventory"]["processors"] || [],
          memory: result["inventory"]["memory"] || [],
          storage: result["inventory"]["storage"] || [],
          network: result["inventory"]["network"] || [],
          infiniband: result["inventory"]["infiniband"] || [],
          bios: result["inventory"]["bios"] || {},
          bmc_info: result["inventory"]["bmc_info"] || {},
          collection_method: result["protocol"],
          captured_at: parse_collected_at(result["collected_at"])
        )
        created << inventory

        # Trigger reconciliation
        Bmc::ReconciliationService.new(node).call
      end

      { created: created.size }
    end

    private

    def parse_collected_at(value)
      Time.zone.parse(value) || Time.current
    rescue TypeError, ArgumentError
      Time.current
    end
  end
end
