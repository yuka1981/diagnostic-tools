# frozen_string_literal: true

module Api
  module V1
    class HeartbeatsController < BaseController
      # POST /api/v1/nodes/:node_uuid/heartbeat
      def create
        node = Node.find_by(uuid: params[:uuid])
        return render_not_found("Node not found") unless node

        node.update!(
          last_heartbeat_at: Time.current,
          agent_version: params[:version]
        )

        render json: { status: "ok", timestamp: Time.current.iso8601 }
      end
    end
  end
end
