# frozen_string_literal: true

module Api
  module V1
    class ProfilingRunsController < BaseController
      before_action :set_run

      def status
        @run.update!(log_content: [ @run.log_content, params[:message] ].compact.join("\n"))
        render json: { success: true }
      end

      def complete
        status_map = { "success" => :success, "failed" => :failed }
        new_status = status_map[params[:status]] || @run.status

        update_params = {
          status: new_status,
          metrics: params[:metrics],
          finished_at: Time.current,
          log_content: params[:log_content],
          error_message: params[:error_message]
        }.compact

        if @run.update(update_params)
          process_artifacts if params[:artifacts].present?
          render json: { success: true, uuid: @run.uuid }
        else
          render json: { error: @run.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      private

      def set_run
        @run = ProfilingRun.find_by!(uuid: params[:uuid])
      end

      def process_artifacts
        params[:artifacts].each do |artifact_data|
          @run.profiling_artifacts.find_or_create_by!(filename: artifact_data[:filename]) do |artifact|
            artifact.file_path = artifact_data[:file_path]
            artifact.file_type = artifact_data[:file_type]
            artifact.file_size = artifact_data[:file_size]
          end
        end
      end
    end
  end
end
