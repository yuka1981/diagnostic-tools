# frozen_string_literal: true

module Bmc
  class InventoryProcessor
    Result = Struct.new(:success, :inventory, :error, keyword_init: true) do
      def success? = success
    end

    def self.call(...)
      new(...).call
    end

    def initialize(node_id:, inventory_data:, collection_method:)
      @node_id = node_id
      @inventory_data = inventory_data || {}
      @collection_method = collection_method
    end

    def call
      node = find_node
      return Result.new(success: false, error: "Node not found") unless node

      return Result.new(success: false, error: "Collection method is not valid") unless valid_collection_method?

      inventory = create_inventory(node)
      if inventory.persisted?
        trigger_reconciliation(node)
        Result.new(success: true, inventory: inventory)
      else
        Result.new(success: false, error: inventory.errors.full_messages.join(", "))
      end
    end

    private

    def find_node
      # Try to find by database id first
      return Node.find_by(id: @node_id) if @node_id.to_s.match?(/\A\d+\z/)

      # Try to find by uuid (node_id field)
      node = Node.find_by(uuid: @node_id)
      return node if node

      # Try to find by hostname (name)
      Node.find_by(hostname: @node_id)
    end

    def create_inventory(node)
      node.bmc_inventories.create(
        processors: @inventory_data[:processors] || [],
        memory: @inventory_data[:memory] || [],
        storage: @inventory_data[:storage] || [],
        network: @inventory_data[:network] || [],
        infiniband: @inventory_data[:infiniband] || [],
        bios: @inventory_data[:bios] || {},
        bmc_info: @inventory_data[:bmc_info] || {},
        collection_method: @collection_method,
        captured_at: Time.current
      )
    end

    def trigger_reconciliation(node)
      Bmc::ReconciliationService.call(node)
    end

    def valid_collection_method?
      BmcInventory.collection_methods.key?(@collection_method.to_s)
    end
  end
end
