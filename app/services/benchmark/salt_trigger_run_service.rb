module Benchmark
  class SaltTriggerRunService
    Result = Struct.new(:success, :error, :jid, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(target_node, benchmark_run:, salt_client: nil, argument_overrides: {})
      @target_node = target_node
      @benchmark_run = benchmark_run
      @salt_client = salt_client || SaltApiClient.new
      @argument_overrides = argument_overrides
    end

    def call
      jid = @salt_client.run_async(
        @target_node.hostname,
        "state.apply",
        mods: state_mod,
        pillar: pillar_data
      )

      @benchmark_run.update!(
        status: :running,
        started_at: Time.current
      )

      Result.new(success: true, jid: jid)
    rescue SaltApiClient::TargetUnreachable, SaltApiClient::TimeoutError, SaltApiClient::ApiError => e
      @benchmark_run.update!(
        status: :failed,
        error_message: e.message,
        finished_at: Time.current
      )
      Result.new(success: false, error: e.message)
    end

    private

    def state_mod
      benchmark_type = @benchmark_run.benchmark_recipe.benchmark_type
      "benchmark.#{benchmark_type}"
    end

    def pillar_data
      {
        run_id: @benchmark_run.uuid,
        work_dir: BenchmarkConfig.work_dir_for(@target_node),
        arguments: merged_arguments
      }
    end

    def merged_arguments
      defaults = @benchmark_run.benchmark_recipe.default_profile || {}
      defaults.deep_merge(@argument_overrides)
    end
  end
end
