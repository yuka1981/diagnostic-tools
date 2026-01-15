# frozen_string_literal: true

module Api
  module V1
    class BenchmarkRunsController < BaseController
      def create
        # Find existing run by uuid if provided
        run = BenchmarkRun.find_by(uuid: params[:run_id])

        if run
          # Try to verify/update node association via UUID sync
          # Only update if we find an EXISTING node with matching UUID (don't create new ones)
          uuid = request.headers["X-Node-ID"]
          if uuid.present?
            existing_node = Node.find_by(uuid: uuid)
            if existing_node && run.node != existing_node
              # UUID sync worked - update association to the correct node
              Rails.logger.info "[BenchmarkRuns] Updating run #{run.uuid} node from #{run.node_id} to #{existing_node.id} via UUID sync"
              run.update!(node: existing_node)
            end
          end

          update_run(run)
        else
          render json: { error: "Benchmark run not found" }, status: :not_found
        end
      end

      private

      def update_run(run)
        # Map agent status to server status
        # agent statuses: UNKNOWN, PASS, FAIL, ERROR
        # server statuses: pending, running, success, failed, cancelled

        status_map = {
          "PASS" => :success,
          "FAIL" => :failed,
          "ERROR" => :failed,
          "RUNNING" => :running # I'll add this to the agent
        }

        update_params = {
          status: status_map[params[:status]] || run.status,
          metrics: params[:metrics],
          started_at: sanitize_timestamp(params[:start_time]),
          finished_at: sanitize_timestamp(params[:end_time]),
          log_content: params[:log_content]
        }.compact

        if run.update(update_params)
          # Process artifacts if provided
          if params[:artifacts].is_a?(Array)
            params[:artifacts].each do |path|
              run.artifact_indices.find_or_create_by(path: path) do |ai|
                ai.file_type = File.extname(path).delete(".")
                # Size could be updated later or passed in payload
              end
            end
          end

          render json: { success: true, run_id: run.uuid }
        else
          render json: { error: run.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # Sanitize timestamp values to filter out invalid dates
      # Go's zero time (0001-01-01) can leak through when omitempty doesn't work as expected
      def sanitize_timestamp(value)
        return nil if value.blank?

        time = Time.zone.parse(value.to_s)
        # Reject timestamps before year 2000 (catches Go's zero time: 0001-01-01)
        return nil if time.nil? || time.year < 2000

        time
      rescue ArgumentError
        nil
      end
    end
  end
end
