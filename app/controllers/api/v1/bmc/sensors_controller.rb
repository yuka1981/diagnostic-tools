# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class SensorsController < Api::V1::BaseController
        # POST /api/v1/bmc/sensors
        def push
          result = ::Bmc::PrometheusPusher.call(
            node_id: params[:node_id],
            sensors: sensor_params
          )

          if result.success?
            render json: { status: "ok" }
          else
            render json: { status: "error", message: result.error }, status: :unprocessable_entity
          end
        end

        private

        def sensor_params
          params.permit(sensors: [ :name, :value, :unit, :status ]).fetch(:sensors, []).map(&:to_h).map(&:deep_symbolize_keys)
        end
      end
    end
  end
end
