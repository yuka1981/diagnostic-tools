# frozen_string_literal: true

module Api
  module V1
    class ProfilingRunsController < BaseController
      class PathTraversalError < StandardError; end

      before_action :set_run
      rescue_from PathTraversalError, with: :handle_path_traversal_error
      rescue_from ArgumentError, with: :handle_argument_error

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
        artifacts_params.each do |artifact_data|
          validated_path = validate_artifact_path!(artifact_data[:file_path])

          @run.profiling_artifacts.find_or_create_by!(filename: artifact_data[:filename]) do |artifact|
            artifact.file_path = validated_path
            artifact.file_type = artifact_data[:file_type]
            artifact.file_size = artifact_data[:file_size]
          end
        end
      end

      def artifacts_params
        params.permit(artifacts: [ :filename, :file_path, :file_type, :file_size ]).fetch(:artifacts, [])
      end

      def validate_artifact_path!(file_path)
        raise ArgumentError, "file_path is required" if file_path.blank?

        base_directory = artifacts_base_directory
        expanded_path = File.expand_path(file_path, base_directory)

        unless expanded_path.start_with?("#{base_directory}/")
          raise PathTraversalError, "Invalid file path: path traversal attempt detected"
        end

        expanded_path
      end

      def artifacts_base_directory
        @artifacts_base_directory ||= begin
          base_path = ENV.fetch("ARTIFACTS_BASE_PATH") { Rails.root.join("storage", "artifacts").to_s }
          File.expand_path(base_path)
        end
      end

      def handle_path_traversal_error(exception)
        Rails.logger.warn("Path traversal attempt detected: #{exception.message}")
        render json: { error: "Invalid file path" }, status: :bad_request
      end

      def handle_argument_error(exception)
        render json: { error: exception.message }, status: :bad_request
      end
    end
  end
end
