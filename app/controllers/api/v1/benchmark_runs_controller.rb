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
        # agent statuses: UNKNOWN, PASS, FAIL, ERROR, RUNNING
        # server statuses: pending, running, success, failed, cancelled

        # Build error message: prefer explicit error_message, fall back to status description
        error_msg = params[:error_message].presence
        if error_msg.blank? && %w[FAIL ERROR].include?(params[:status])
          error_msg = "Benchmark reported #{params[:status]} status"
        end

        update_params = {
          status: BenchmarkRun.status_from_agent(params[:status]) || run.status,
          metrics: params[:metrics],
          started_at: sanitize_timestamp(params[:start_time]),
          finished_at: sanitize_timestamp(params[:end_time]),
          log_content: params[:log_content],
          error_message: error_msg
        }.compact

        if run.update(update_params)
          # Process artifact uploads (new: with file contents)
          # Returns set of uploaded filenames to skip in legacy processing
          uploaded_filenames = params[:artifact_uploads].is_a?(Array) ? process_artifact_uploads(run) : Set.new

          # Process legacy artifacts (paths only, for backwards compatibility)
          # Skip files that were already uploaded via artifact_uploads
          if params[:artifacts].is_a?(Array)
            params[:artifacts].each do |path|
              filename = File.basename(path)
              next if uploaded_filenames.include?(filename)

              run.artifact_indices.find_or_create_by(path: path) do |ai|
                ai.file_type = File.extname(path).delete(".")
              end
            end
          end

          render json: { success: true, run_id: run.uuid }
        else
          render json: { error: run.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # Process artifact uploads and return Set of successfully uploaded filenames
      def process_artifact_uploads(run)
        storage_dir = artifact_storage_dir(run)
        FileUtils.mkdir_p(storage_dir)
        uploaded_filenames = Set.new

        params[:artifact_uploads].each do |upload|
          filename = upload[:filename]
          content = upload[:content]
          file_type = upload[:file_type]
          size = upload[:size]

          next if filename.blank? || content.blank?

          # Sanitize filename to prevent directory traversal
          safe_filename = File.basename(filename)
          stored_path = File.join(storage_dir, safe_filename)

          begin
            # Decode base64 content and write to file
            decoded_content = Base64.decode64(content)
            File.binwrite(stored_path, decoded_content)

            # Create or update artifact index with stored_path
            run.artifact_indices.find_or_initialize_by(path: stored_path).tap do |ai|
              ai.stored_path = stored_path
              ai.file_type = file_type.presence || File.extname(safe_filename).delete(".")
              ai.size = size.presence || decoded_content.bytesize
              ai.save!
            end

            uploaded_filenames << safe_filename
            Rails.logger.info "[BenchmarkRuns] Stored artifact: #{stored_path} (#{decoded_content.bytesize} bytes)"
          rescue StandardError => e
            Rails.logger.error "[BenchmarkRuns] Failed to store artifact #{filename}: #{e.message}"
          end
        end

        uploaded_filenames
      end

      def artifact_storage_dir(run)
        base_dir = Rails.configuration.x.artifacts_storage_path.presence || Rails.root.join("storage", "artifacts")
        File.join(base_dir, run.uuid)
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
