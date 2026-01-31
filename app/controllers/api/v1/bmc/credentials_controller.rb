# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class CredentialsController < Api::V1::BaseController
        before_action :require_bmc_access!

        def index
          global_default = BmcCredential.global_default
          credentials = []

          Node.find_each do |node|
            cred = node.bmc_credential || global_default
            next unless cred

            credentials << {
              node_id: node.id,
              hostname: node.hostname,
              bmc_address: node.bmc_credential&.bmc_address || cred.bmc_address,
              username: cred.username,
              password: cred.password,
              protocol: cred.protocol,
              port: cred.port,
              verify_ssl: cred.verify_ssl
            }
          end

          render json: { credentials: credentials }
        end

        private

        def require_bmc_access!
          return if current_api_key&.bmc_access?

          render json: { error: "Forbidden: BMC credential access not granted for this API key" }, status: :forbidden
        end
      end
    end
  end
end
