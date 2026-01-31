# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class SensorsController < ApplicationController
        before_action :authenticate_user!

        def show
          node = Node.find(params[:node_id])
          service = ::Bmc::SensorQueryService.new(
            node,
            sensor_type: params[:sensor_type],
            range: params[:range] || "24h"
          )

          render json: {
            chart_data: service.chart_data,
            current_readings: service.current_readings
          }
        end
      end
    end
  end
end
