# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class CredentialsController < Api::V1::BaseController
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
      end
    end
  end
end
