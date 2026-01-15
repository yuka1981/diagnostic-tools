# frozen_string_literal: true

module Benchmark
  class TriggerJob < ApplicationJob
    queue_as :default

    def perform(node, run, server_url, agent_token, argument_overrides = {})
      trigger_service = Benchmark::TriggerRunService.new(
        node,
        log_path: run.log_path,
        run_id: run.uuid,
        server_url: server_url,
        agent_token: agent_token,
        benchmark_recipe: run.benchmark_recipe,
        argument_overrides: argument_overrides
      )
      result = trigger_service.call

      # Reload to check current state - status may have changed during SSH call
      # (e.g., user cancelled, or fast agent already reported completion)
      run.reload
      return unless run.pending?

      if result.success?
        # Optimistically mark as running since SSH command was accepted
        # Agent will update to success/failed when complete
        run.update!(status: :running, started_at: Time.current, log_content: result.output)
      else
        # Store both error message and full SSH output for debugging
        run.update!(status: :failed, error_message: result.error, log_content: result.output)
      end
    end
  end
end
