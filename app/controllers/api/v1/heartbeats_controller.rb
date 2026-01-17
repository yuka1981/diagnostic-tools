# frozen_string_literal: true

module Api
  module V1
    class HeartbeatsController < BaseController
      def create
        node = find_node
        return render_not_found("Node not found") unless node

        node.update!(
          last_heartbeat_at: Time.current,
          agent_version: params[:version]
        )

        render json: { status: "ok" }, status: :ok
      end

      private

      def find_node
        # Try to find by UUID from URL params
        Node.find_by(uuid: params[:id])
      end
    end
  end
end
