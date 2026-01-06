# frozen_string_literal: true

module Api
  module V1
    class BenchmarkRunsController < BaseController
      def create
        # Find existing run by uuid if provided
        run = BenchmarkRun.find_by(uuid: params[:run_id])

        if run
          update_run(run)
        else
          # Fallback: create a new one if not found (optional behavior)
          # But for "tracing", we expect it to exist
          render json: { error: "Benchmark run not found" }, status: :not_found
        end
      end

      def progress
        run = BenchmarkRun.find_by(uuid: params[:id])
        return render_not_found("Benchmark run not found") unless run

        status_param = normalized_status_param

        if status_param.present? && !BenchmarkRun.statuses.key?(status_param)
          return render_bad_request("Invalid status")
        end

        attributes = {
          last_heartbeat_at: Time.current
        }
        attributes[:status] = status_param if status_param.present?
        attributes[:current_phase] = progress_params[:phase] if progress_params.key?(:phase)

        if run.update(attributes)
          render json: { success: true, run_id: run.uuid }
        else
          render json: { error: run.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      private

      def update_run(run)
        # Map agent status to server status
        # agent statuses: UNKNOWN, PASS, FAIL, ERROR
        # server statuses: pending, running, success, failed, lost

        status_map = {
          "PASS" => :success,
          "FAIL" => :failed,
          "ERROR" => :failed,
          "RUNNING" => :running
        }

        update_params = {
          status: status_map[params[:status]] || run.status,
          metrics: params[:metrics],
          started_at: params[:start_time],
          finished_at: params[:end_time],
          last_heartbeat_at: Time.current
        }

        if run.update(update_params)
          render json: { success: true, run_id: run.uuid }
        else
          render json: { error: run.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def progress_params
        params.permit(:status, :phase)
      end

      def normalized_status_param
        progress_params[:status]&.to_s&.downcase
      end
    end
  end
end
