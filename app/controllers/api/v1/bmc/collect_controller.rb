# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class CollectController < ApplicationController
        before_action :authenticate_user!

        def sensors
          result = ::Bmc::SaltTriggerService.new.collect_sensors(node: params[:node])
          render json: result
        end

        def inventory
          result = ::Bmc::SaltTriggerService.new.collect_inventory(node: params[:node])
          render json: result
        end
      end
    end
  end
end
