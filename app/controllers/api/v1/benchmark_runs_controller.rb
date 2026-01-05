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
          started_at: params[:start_time],
          finished_at: params[:end_time]
        }

        if run.update(update_params)
          render json: { success: true, run_id: run.uuid }
        else
          render json: { error: run.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end
    end
  end
end
