module Salt
  class BenchmarkResultService
    def initialize(benchmark_run:, job_return:, salt_client: nil)
      @benchmark_run = benchmark_run
      @job_return = job_return
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      node_hostname = @benchmark_run.node.hostname
      minion_return = @job_return.dig(node_hostname)

      unless minion_return.is_a?(Hash) && minion_return["return"].is_a?(Hash)
        @benchmark_run.update!(
          status: :failed,
          error_message: "Invalid job return data: #{minion_return.inspect.truncate(500)}",
          finished_at: Time.current
        )
        return false
      end

      result = minion_return["return"]
      status = BenchmarkRun.status_from_agent(result["status"]) || :failed
      log_file_path = write_log_content(result["log_content"])

      @benchmark_run.update!(
        status: status,
        metrics: result["metrics"] || {},
        started_at: parse_time(result["start_time"]) || @benchmark_run.started_at,
        finished_at: parse_time(result["end_time"]) || Time.current,
        log_path: log_file_path,
        error_message: result["error_message"]
      )

      fetch_artifacts(result["artifacts"] || [])
      true
    rescue StandardError => e
      Rails.logger.error("[BenchmarkResultService] Processing failed: #{e.message}")
      false
    end

    private

    def write_log_content(content)
      return nil unless content.present?

      content = content.truncate(10_000_000) if content.bytesize > 10_000_000 # 10MB cap

      log_dir = Rails.root.join("storage", "benchmark_logs")
      FileUtils.mkdir_p(log_dir)
      path = log_dir.join("#{@benchmark_run.uuid}.log")
      File.write(path, content)
      path.to_s
    end

    def fetch_artifacts(artifact_paths)
      artifact_paths.each do |path|
        @salt_client.run(@benchmark_run.node.hostname, "cp.push", path: path)
      rescue SaltApiClient::ApiError => e
        Rails.logger.warn("Failed to fetch artifact #{path}: #{e.message}")
      end
    end

    def parse_time(time_string)
      return nil unless time_string.present?
      Time.parse(time_string)
    rescue ArgumentError
      nil
    end
  end
end
