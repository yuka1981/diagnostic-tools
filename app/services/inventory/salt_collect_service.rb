module Inventory
  class SaltCollectService
    SALT_TIMEOUT = 120

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
      # Ensure custom Salt modules are available on the minion (fire-and-forget via async)
      sync_modules_async

      grains = @salt_client.run(@target_node.hostname, "grains.items", timeout: SALT_TIMEOUT)
      dmi = safe_collect("inventory.collect_dmi")
      numa = safe_collect("inventory.collect_numa")
      network_v2 = safe_collect("inventory.collect_network_v2")
      cpu_topology = safe_collect("inventory.collect_cpu")
      lscpu = cpu_topology.is_a?(Hash) ? nil : safe_cmd_run("lscpu")
      meminfo = safe_collect("inventory.collect_meminfo")
      disk_usage = safe_collect("disk.usage")
      disk_blkid = safe_collect("disk.blkid")

      mapped = Salt::InventoryMapper.new(
        grains: grains,
        dmi: dmi,
        numa: numa,
        network_v2: network_v2,
        cpu_topology: cpu_topology,
        lscpu: lscpu,
        meminfo: meminfo,
        disk_usage: disk_usage,
        disk_blkid: disk_blkid
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

    def sync_modules_async
      @salt_client.run_async(@target_node.hostname, "saltutil.sync_modules")
    rescue SaltApiClient::ApiError, SaltApiClient::TargetUnreachable, SaltApiClient::AuthenticationError => e
      Rails.logger.warn("Module sync failed for #{@target_node.hostname}: #{e.message}, continuing with cached modules")
    end

    def safe_collect(function)
      @salt_client.run(@target_node.hostname, function, timeout: SALT_TIMEOUT)
    rescue SaltApiClient::ApiError, SaltApiClient::TargetUnreachable => e
      Rails.logger.warn("Salt custom module #{function} failed: #{e.message}")
      nil
    end

    def safe_cmd_run(command)
      result = @salt_client.run(@target_node.hostname, "cmd.run", arg: [ command ], timeout: SALT_TIMEOUT)
      result.is_a?(String) ? result : nil
    rescue SaltApiClient::ApiError, SaltApiClient::TargetUnreachable => e
      Rails.logger.warn("Salt cmd.run '#{command}' failed: #{e.message}")
      nil
    end
  end
end
