# frozen_string_literal: true

module Api
  module V1
    class InventoryController < BaseController
      def push
        # Parse and validate request body
        parsed_body = parse_request_body
        return if performed?

        # Validate required identifier
        # Agent sends hostname inside 'host' object
        hostname = parsed_body.dig(:host, :hostname) || parsed_body[:hostname]
        node_id = parsed_body[:node_id]
        uuid = request.headers["X-Node-ID"]

        unless hostname.present? || node_id.present? || uuid.present?
          return render_bad_request("Either hostname, node_id or X-Node-ID header is required")
        end

        # Build state data from request
        raw_json = build_raw_json(parsed_body)

        # Call ProcessStateService
        result = Inventory::ProcessStateService.new(
          hostname: hostname,
          node_id: node_id,
          uuid: uuid,
          raw_json: raw_json
        ).call

        if result.success?
          render json: {
            success: true,
            state_created: result.state_created,
            node_state_id: result.node_state&.id
          }, status: :ok
        else
          handle_service_error(result)
        end
      end

      private

      def parse_request_body
        body = request.body.read
        if body.blank?
          render_bad_request("Request body cannot be empty")
          return {}
        end

        JSON.parse(body, symbolize_names: true)
      rescue JSON::ParserError => e
        render_bad_request("Invalid JSON: #{e.message}")
        {}
      end

      def build_raw_json(parsed_body)
        parsed_body.slice(:host, :cpu, :memory, :disks, :network)
      end

      def handle_service_error(result)
        case result.error_code
        when :not_found
          render_not_found(result.error)
        else
          render_bad_request(result.error)
        end
      end
    end
  end
end
