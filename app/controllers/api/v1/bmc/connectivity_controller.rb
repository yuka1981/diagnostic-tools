# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class ConnectivityController < Api::V1::BaseController
        def check
          result = ::Bmc::SaltTriggerService.new.check_connectivity(node: params[:node])
          render json: result
        end
      end
    end
  end
end
