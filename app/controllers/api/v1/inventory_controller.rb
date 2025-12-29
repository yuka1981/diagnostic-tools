# frozen_string_literal: true

module Api
  module V1
    class InventoryController < BaseController
      def push
        # Parse and validate request body
        parsed_body = parse_request_body
        return if performed?

        # Validate required identifier
        hostname = parsed_body[:hostname]
        node_id = parsed_body[:node_id]

        unless hostname.present? || node_id.present?
          return render_bad_request("Either hostname or node_id is required")
        end

        # Build state data from request
        raw_json = build_raw_json(parsed_body)

        # Call ProcessStateService
        result = Inventory::ProcessStateService.new(
          hostname: hostname,
          node_id: node_id,
          raw_json: raw_json
        ).call

        if result.success?
          render json: {
            success: true,
            state_created: result.state_created,
            node_state_id: result.node_state&.id
          }, status: :ok
        else
          handle_service_error(result.error)
        end
      end

      private

      def parse_request_body
        if request.body.read.blank?
          render_bad_request("Request body cannot be empty")
          return {}
        end

        request.body.rewind
        JSON.parse(request.body.read, symbolize_names: true)
      rescue JSON::ParserError => e
        render_bad_request("Invalid JSON: #{e.message}")
        {}
      end

      def build_raw_json(parsed_body)
        {
          cpu_info: parsed_body[:cpu_info],
          mem_info: parsed_body[:mem_info],
          disk_info: parsed_body[:disk_info],
          net_info: parsed_body[:net_info]
        }
      end

      def handle_service_error(error)
        case error
        when /not found/i
          render_not_found(error)
        else
          render_bad_request(error)
        end
      end
    end
  end
end
