# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class InventoryController < Api::V1::BaseController
        # POST /api/v1/bmc/inventory
        def push
          result = ::Bmc::InventoryProcessor.call(
            node_id: params[:node_id],
            inventory_data: inventory_params,
            collection_method: params[:collection_method]
          )

          if result.success?
            render json: { status: "ok", inventory_id: result.inventory.id }
          else
            render json: { status: "error", message: result.error }, status: :unprocessable_entity
          end
        end

        private

        def inventory_params
          params.permit(
            processors: [ :socket, :model, :cores, :freq_base, :freq_max, :serial ],
            memory: [ :slot, :size_gb, :speed_mhz, :manufacturer, :serial, :type ],
            storage: [ :name, :capacity, :model, :serial, :interface, :health ],
            network: [ :name, :mac, :model, :speed, :firmware ],
            infiniband: [ :hca, :port_state, :firmware, :guid ],
            bios: [ :vendor, :version, :release_date ],
            bmc_info: [ :model, :firmware, :ip ]
          ).to_h.deep_symbolize_keys
        end
      end
    end
  end
end
