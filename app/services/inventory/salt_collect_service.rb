module Inventory
  class SaltCollectService
    Result = Struct.new(:success, :error, :state_created, :node_state, :error_code, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(target_node, salt_client: nil)
      @target_node = target_node
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      grains = @salt_client.run(@target_node.hostname, "grains.items")
      dmi = safe_collect("inventory.collect_dmi")
      numa = safe_collect("inventory.collect_numa")
      network_v2 = safe_collect("inventory.collect_network_v2")
      cpu_topology = safe_collect("inventory.collect_cpu")
      lscpu = cpu_topology ? nil : safe_cmd_run("lscpu")

      mapped = Salt::InventoryMapper.new(
        grains: grains,
        dmi: dmi,
        numa: numa,
        network_v2: network_v2,
        cpu_topology: cpu_topology,
        lscpu: lscpu
      ).call

      process_result = Inventory::ProcessStateService.new(
        node_id: @target_node.id,
        raw_json: mapped
      ).call

      Result.new(
        success: process_result.success?,
        error: process_result.error,
        state_created: process_result.state_created,
        node_state: process_result.node_state
      )
    rescue SaltApiClient::TargetUnreachable => e
      Result.new(success: false, error: e.message)
    rescue SaltApiClient::TimeoutError => e
      Result.new(success: false, error: e.message)
    rescue SaltApiClient::AuthenticationError => e
      Result.new(success: false, error: "Salt API authentication failed: #{e.message}")
    end

    private

    def safe_collect(function)
      @salt_client.run(@target_node.hostname, function)
    rescue SaltApiClient::ApiError => e
      Rails.logger.warn("Salt custom module #{function} failed: #{e.message}")
      nil
    end

    def safe_cmd_run(command)
      result = @salt_client.run(@target_node.hostname, "cmd.run", arg: [ command ])
      result.is_a?(String) ? result : nil
    rescue SaltApiClient::ApiError => e
      Rails.logger.warn("Salt cmd.run '#{command}' failed: #{e.message}")
      nil
    end
  end
end
