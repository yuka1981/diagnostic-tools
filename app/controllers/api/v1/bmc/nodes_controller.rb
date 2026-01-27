# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class NodesController < Api::V1::BaseController
        # GET /api/v1/bmc/nodes
        # Returns list of nodes with BMC credentials for the collector
        def index
          nodes = Node.includes(:bmc_credential)
                      .where.not(bmc_address: [ nil, "" ])

          render json: nodes.map { |n| node_with_credentials(n) }
        end

        private

        def node_with_credentials(node)
          credential = node.bmc_credential_for_connection

          {
            id: node.id,
            node_id: node.uuid,
            name: node.hostname,
            bmc_address: node.bmc_address,
            bmc_username: credential&.username,
            bmc_password: credential&.password,
            bmc_protocol: credential&.protocol || "auto",
            bmc_port: credential&.port,
            bmc_verify_ssl: credential&.verify_ssl
          }
        end
      end
    end
  end
end
