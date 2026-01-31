# frozen_string_literal: true

module Bmc
  class SaltTriggerService
    def initialize
      @client = SaltApiClient.new
    end

    def collect_sensors(node: nil)
      kwargs = {}
      kwargs[:node] = node if node
      @client.run_runner("qis_bmc.collect_sensors", kwarg: kwargs)
    end

    def collect_inventory(node: nil)
      kwargs = {}
      kwargs[:node] = node if node
      @client.run_runner("qis_bmc.collect_inventory", kwarg: kwargs)
    end

    def check_connectivity(node: nil)
      kwargs = {}
      kwargs[:node] = node if node
      @client.run_runner("qis_bmc.check_connectivity", kwarg: kwargs)
    end
  end
end
