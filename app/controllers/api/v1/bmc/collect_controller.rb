# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class CollectController < Api::V1::BaseController
        # POST /api/v1/bmc/collect/inventory
        def inventory
          node = find_node
          return render_not_found("Node not found") unless node

          job = ::Bmc::CollectInventoryJob.perform_later(node.id)

          render json: {
            status: "queued",
            job_id: job.job_id,
            node_id: node.id,
            node_name: node.hostname
          }
        end

        private

        def find_node
          node_identifier = params[:node_id]
          return nil if node_identifier.blank?

          # Try to find by database id first (numeric string)
          if node_identifier.to_s.match?(/\A\d+\z/)
            node = Node.find_by(id: node_identifier)
            return node if node
          end

          # Try to find by uuid
          node = Node.find_by(uuid: node_identifier)
          return node if node

          # Try to find by hostname
          Node.find_by(hostname: node_identifier)
        end
      end
    end
  end
end
