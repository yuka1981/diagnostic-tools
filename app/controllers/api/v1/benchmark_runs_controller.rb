# frozen_string_literal: true

module Api
  module V1
    class BenchmarkRunsController < BaseController
      def create
        # Identify node from X-Node-ID header
        uuid = request.headers["X-Node-ID"]
        node = find_or_register_node(uuid) if uuid.present?

        # Find existing run by uuid if provided
        run = BenchmarkRun.find_by(uuid: params[:run_id])

        if run
          # Ensure run is associated with the reporting node if we found one
          run.update!(node: node) if node && run.node != node
          update_run(run)
        else
          render json: { error: "Benchmark run not found" }, status: :not_found
        end
      end

      private

      def find_or_register_node(uuid)
        Node.find_or_create_by(uuid: uuid) do |n|
          n.hostname = "node-#{uuid[0..7]}"
          n.ip = request.remote_ip
          n.source = :agent_push
        end
      end

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
          started_at: params[:start_time],
          finished_at: params[:end_time]
        }

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
    end
  end
end
